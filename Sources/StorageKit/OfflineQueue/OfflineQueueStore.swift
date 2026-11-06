import Foundation

/// Persistent queue for operations that need to be executed when online
/// Stores operations with retry logic and automatic replay
public actor OfflineQueueStore {
    
    public static let shared = OfflineQueueStore()
    
    private let fileManager = FileManager.default
    private let queueDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isProcessing = false
    private var observers: [UUID: @Sendable (QueueEvent) async -> Void] = [:]
    private var processedNonces: Set<String> = []
    private let maxNonceAge: TimeInterval = 86400
    private var nonceTimestamps: [String: Date] = [:]
    
    private init() {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.queueDirectory = documentsPath.appendingPathComponent("OfflineQueue", isDirectory: true)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Enqueue an operation to be executed later
    public func enqueue<T: Codable & Sendable>(_ operation: QueuedOperation<T>) async throws {
        let nonce = operation.nonce ?? UUID().uuidString
        
        if processedNonces.contains(nonce) {
            throw QueueError.replayDetected(nonce: nonce)
        }
        
        let item = QueueItem(
            id: operation.id,
            type: operation.type,
            priority: operation.priority,
            data: try encoder.encode(operation.data),
            createdAt: Date(),
            retryCount: 0,
            maxRetries: operation.maxRetries,
            expiresAt: operation.expiresAt,
            nonce: nonce
        )
        
        try await save(item)
        await notifyObservers(.enqueued(item.id, item.type))
    }
    
    /// Get all pending operations
    public func getPending() async throws -> [QueueItem] {
        let files = try fileManager.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        var items: [QueueItem] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let item = try? decoder.decode(QueueItem.self, from: data) {
                // Skip expired items
                if let expiresAt = item.expiresAt, expiresAt < Date() {
                    try? fileManager.removeItem(at: file)
                    continue
                }
                items.append(item)
            }
        }
        
        // Sort by priority (high to low) then by creation date (old to new)
        return items.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
    
    /// Get operation by ID
    public func get(id: String) async throws -> QueueItem? {
        let fileURL = queueDirectory.appendingPathComponent("\(id).json")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(QueueItem.self, from: data)
    }
    
    /// Remove operation from queue
    public func remove(id: String) async throws {
        let fileURL = queueDirectory.appendingPathComponent("\(id).json")
        try fileManager.removeItem(at: fileURL)
        await notifyObservers(.removed(id))
    }
    
    /// Mark operation as failed and increment retry count
    public func markFailed(id: String, error: Error) async throws {
        guard var item = try await get(id: id) else { return }
        
        item.retryCount += 1
        item.lastError = error.localizedDescription
        item.lastAttemptAt = Date()
        
        if item.retryCount >= item.maxRetries {
            // Max retries reached - remove from queue
            try await remove(id: id)
            await notifyObservers(.failed(id, error))
        } else {
            // Save updated item
            try await save(item)
            await notifyObservers(.retrying(id, item.retryCount))
        }
    }
    
    /// Process all pending operations
    public func processQueue(
        executor: @escaping (QueueItem) async throws -> Void
    ) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let pending = try await getPending()
            await notifyObservers(.processingStarted(pending.count))
            
            for item in pending {
                do {
                    if processedNonces.contains(item.nonce) {
                        try await remove(id: item.id)
                        continue
                    }
                    
                    try await executor(item)
                    
                    processedNonces.insert(item.nonce)
                    nonceTimestamps[item.nonce] = Date()
                    
                    try await remove(id: item.id)
                    await notifyObservers(.completed(item.id))
                } catch {
                    try await markFailed(id: item.id, error: error)
                }
            }
            
            cleanupOldNonces()
            
            await notifyObservers(.processingCompleted)
        } catch {
            await notifyObservers(.processingFailed(error))
        }
    }
    
    /// Get queue statistics
    public func getStats() async throws -> QueueStats {
        let items = try await getPending()
        
        let byPriority = Dictionary(grouping: items) { $0.priority }
        let byType = Dictionary(grouping: items) { $0.type }
        
        let oldestItem = items.min(by: { $0.createdAt < $1.createdAt })
        let itemsWithRetries = items.filter { $0.retryCount > 0 }.count
        
        return QueueStats(
            totalItems: items.count,
            itemsByPriority: byPriority.mapValues { $0.count },
            itemsByType: byType.mapValues { $0.count },
            oldestItemAge: oldestItem.map { Date().timeIntervalSince($0.createdAt) },
            itemsWithRetries: itemsWithRetries
        )
    }
    
    /// Clear all items from queue
    public func clear() async throws {
        let files = try fileManager.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        for file in files {
            try fileManager.removeItem(at: file)
        }
        
        await notifyObservers(.cleared)
    }
    
    /// Clear expired items
    public func clearExpired() async throws {
        let items = try await getPending()
        let now = Date()
        
        for item in items {
            if let expiresAt = item.expiresAt, expiresAt < now {
                try await remove(id: item.id)
            }
        }
    }
    
    // MARK: - Observers
    
    /// Add observer for queue events
    public func addObserver(_ observer: @escaping @Sendable (QueueEvent) async -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }
    
    /// Remove observer
    public func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }
    
    // MARK: - Private Helpers
    
    private func save(_ item: QueueItem) async throws {
        let fileURL = queueDirectory.appendingPathComponent("\(item.id).json")
        let data = try encoder.encode(item)
        try data.write(to: fileURL, options: .atomic)
    }
    
    private func notifyObservers(_ event: QueueEvent) async {
        for observer in observers.values {
            await observer(event)
        }
    }
    
    private func cleanupOldNonces() {
        let now = Date()
        let expiredNonces = nonceTimestamps.filter { _, timestamp in
            now.timeIntervalSince(timestamp) > maxNonceAge
        }.map { $0.key }
        
        for nonce in expiredNonces {
            processedNonces.remove(nonce)
            nonceTimestamps.removeValue(forKey: nonce)
        }
    }
}

// MARK: - Models

/// Operation to be queued
public struct QueuedOperation<T: Codable & Sendable>: Sendable {
    public let id: String
    public let type: String
    public let priority: QueuePriority
    public let data: T
    public let maxRetries: Int
    public let expiresAt: Date?
    public let nonce: String?
    
    public init(
        id: String = UUID().uuidString,
        type: String,
        priority: QueuePriority = .normal,
        data: T,
        maxRetries: Int = 3,
        expiresAt: Date? = nil,
        nonce: String? = nil
    ) {
        self.id = id
        self.type = type
        self.priority = priority
        self.data = data
        self.maxRetries = maxRetries
        self.expiresAt = expiresAt
        self.nonce = nonce
    }
}

/// Stored queue item
public struct QueueItem: Codable, Sendable {
    public let id: String
    public let type: String
    public let priority: QueuePriority
    public let data: Data
    public let createdAt: Date
    public var retryCount: Int
    public let maxRetries: Int
    public let expiresAt: Date?
    public var lastError: String?
    public var lastAttemptAt: Date?
    public let nonce: String
    
    /// Decode data as specific type
    public func decode<T: Decodable>(as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}

/// Queue priority levels
public enum QueuePriority: Int, Codable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
}

/// Queue events for observation
public enum QueueEvent: Sendable {
    case enqueued(String, String)
    case removed(String)
    case completed(String)
    case failed(String, Error)
    case retrying(String, Int)
    case processingStarted(Int)
    case processingCompleted
    case processingFailed(Error)
    case cleared
}

public enum QueueError: Error {
    case replayDetected(nonce: String)
}

/// Queue statistics
public struct QueueStats: Sendable {
    public let totalItems: Int
    public let itemsByPriority: [QueuePriority: Int]
    public let itemsByType: [String: Int]
    public let oldestItemAge: TimeInterval?
    public let itemsWithRetries: Int
    
    public var isEmpty: Bool { totalItems == 0 }
    public var hasFailures: Bool { itemsWithRetries > 0 }
}

// MARK: - Convenience Extensions

public extension OfflineQueueStore {
    /// Enqueue a simple operation with default settings
    func enqueue<T: Codable & Sendable>(
        type: String,
        data: T,
        priority: QueuePriority = .normal
    ) async throws {
        let operation = QueuedOperation(
            type: type,
            priority: priority,
            data: data
        )
        try await enqueue(operation)
    }
}

// MARK: - Usage Examples

/*
 Example 1: Enqueue a message send operation
 
 struct SendMessageData: Codable, Sendable {
     let messageId: String
     let content: String
     let recipientId: String
 }
 
 let data = SendMessageData(
     messageId: "msg_123",
     content: "Hello",
     recipientId: "user_456"
 )
 
 try await OfflineQueueStore.shared.enqueue(
     type: "send_message",
     data: data,
     priority: .high
 )
 
 Example 2: Process queue when online
 
 await OfflineQueueStore.shared.processQueue { item in
     switch item.type {
     case "send_message":
         let data = try item.decode(as: SendMessageData.self)
         try await messageService.send(data)
     case "update_profile":
         let data = try item.decode(as: UpdateProfileData.self)
         try await profileService.update(data)
     default:
         throw QueueError.unknownType(item.type)
     }
 }
 
 Example 3: Monitor queue events
 
 let observerId = await OfflineQueueStore.shared.addObserver { event in
     switch event {
     case .enqueued(let id, let type):
         print("Enqueued: \(type) (\(id))")
     case .completed(let id):
         print("Completed: \(id)")
     case .failed(let id, let error):
         print("Failed: \(id) - \(error)")
     default:
         break
     }
 }
 
 Example 4: Get queue statistics
 
 let stats = try await OfflineQueueStore.shared.getStats()
 print("Total items: \(stats.totalItems)")
 print("High priority: \(stats.itemsByPriority[.high] ?? 0)")
 print("Has failures: \(stats.hasFailures)")
 */
