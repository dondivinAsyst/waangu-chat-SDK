//
//  PendingStateGuard.swift
//  CoreKit
//
//  Makes pending states visible and trackable
//  Ensures operations in pending state are properly monitored
//

import Foundation

/// Guards and tracks pending states
/// Makes pending operations visible to users and system
public actor PendingStateGuard {
    
    public static let shared = PendingStateGuard()
    
    private var pendingOperations: [String: PendingOperation] = [:]
    private var observers: [UUID: @Sendable (PendingOperation) -> Void] = [:]
    
    private init() {}
    
    public struct PendingOperation: Sendable {
        public let id: String
        public let type: OperationType
        public let startedAt: Date
        public let timeout: TimeInterval
        public let metadata: [String: String]
        public var status: PendingStatus
        
        public init(id: String, type: OperationType, startedAt: Date, timeout: TimeInterval, metadata: [String: String], status: PendingStatus) {
            self.id = id
            self.type = type
            self.startedAt = startedAt
            self.timeout = timeout
            self.metadata = metadata
            self.status = status
        }
        
        public var isExpired: Bool {
            let elapsed = Date().timeIntervalSince(startedAt)
            return elapsed > timeout
        }
        
        public var elapsedTime: TimeInterval {
            return Date().timeIntervalSince(startedAt)
        }
        
        public var remainingTime: TimeInterval {
            return max(0, timeout - elapsedTime)
        }
    }
    
    public enum OperationType: String, Sendable {
        case payment
        case messageUpload
        case fileUpload
        case sync
        case authentication
        case apiRequest
        case dataProcessing
        case other
    }
    
    public enum PendingStatus: String, Sendable {
        case pending
        case processing
        case waitingForBackend
        case retrying
        case almostTimeout
    }
    
    public enum PendingError: Error, Sendable {
        case timeout
        case notFound
        case alreadyCompleted
    }
    
    // MARK: - Public API
    
    /// Register a pending operation
    public func registerPending(
        id: String,
        type: OperationType,
        timeout: TimeInterval = 30.0,
        metadata: [String: String] = [:]
    ) {
        let operation = PendingOperation(
            id: id,
            type: type,
            startedAt: Date(),
            timeout: timeout,
            metadata: metadata,
            status: .pending
        )
        
        pendingOperations[id] = operation
        notifyObservers(operation)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "register_pending", "id": id, "type": type.rawValue]
            )
        }
    }
    
    /// Update pending operation status
    public func updateStatus(id: String, status: PendingStatus) throws {
        guard var operation = pendingOperations[id] else {
            throw PendingError.notFound
        }
        
        operation.status = status
        pendingOperations[id] = operation
        notifyObservers(operation)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "update_pending_status", "id": id, "status": status.rawValue]
            )
        }
    }
    
    /// Complete a pending operation
    public func completePending(id: String) throws {
        guard pendingOperations[id] != nil else {
            throw PendingError.notFound
        }
        
        pendingOperations.removeValue(forKey: id)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "complete_pending", "id": id]
            )
        }
    }
    
    /// Get pending operation
    public func getPending(id: String) -> PendingOperation? {
        return pendingOperations[id]
    }
    
    /// Get all pending operations
    public func getAllPending() -> [PendingOperation] {
        return Array(pendingOperations.values)
    }
    
    /// Get pending operations by type
    public func getPendingByType(_ type: OperationType) -> [PendingOperation] {
        return pendingOperations.values.filter { $0.type == type }
    }
    
    /// Check if operation is pending
    public func isPending(id: String) -> Bool {
        return pendingOperations[id] != nil
    }
    
    /// Get expired operations
    public func getExpiredOperations() -> [PendingOperation] {
        return pendingOperations.values.filter { $0.isExpired }
    }
    
    /// Clean up expired operations
    public func cleanupExpired() -> [String] {
        let expired = getExpiredOperations()
        let expiredIds = expired.map { $0.id }
        
        for id in expiredIds {
            pendingOperations.removeValue(forKey: id)
            
            Task {
                await AuditBreadcrumb.shared.record(
                    action: .errorOccurred,
                    category: .system,
                    metadata: ["operation": "pending_timeout", "id": id]
                )
            }
        }
        
        return expiredIds
    }
    
    /// Update almost-timeout operations
    public func updateAlmostTimeout(threshold: TimeInterval = 5.0) {
        for (id, var operation) in pendingOperations {
            if operation.remainingTime <= threshold && operation.status != .almostTimeout {
                operation.status = .almostTimeout
                pendingOperations[id] = operation
                notifyObservers(operation)
            }
        }
    }
    
    /// Add observer for pending operations
    public func addObserver(_ observer: @escaping @Sendable (PendingOperation) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }
    
    /// Remove observer
    public func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
    
    /// Get statistics
    public func getStatistics() -> PendingStatistics {
        let operations = Array(pendingOperations.values)
        let byType = Dictionary(grouping: operations, by: { $0.type })
        let byStatus = Dictionary(grouping: operations, by: { $0.status })
        
        return PendingStatistics(
            totalPending: operations.count,
            byType: byType.mapValues { $0.count },
            byStatus: byStatus.mapValues { $0.count },
            expiredCount: operations.filter { $0.isExpired }.count,
            almostTimeoutCount: operations.filter { $0.status == .almostTimeout }.count
        )
    }
    
    // MARK: - Private Helpers
    
    private func notifyObservers(_ operation: PendingOperation) {
        for observer in observers.values {
            observer(operation)
        }
    }
}

// MARK: - Supporting Types

public struct PendingStatistics: Sendable {
    public let totalPending: Int
    public let byType: [PendingStateGuard.OperationType: Int]
    public let byStatus: [PendingStateGuard.PendingStatus: Int]
    public let expiredCount: Int
    public let almostTimeoutCount: Int
    
    public init(totalPending: Int, byType: [PendingStateGuard.OperationType: Int], byStatus: [PendingStateGuard.PendingStatus: Int], expiredCount: Int, almostTimeoutCount: Int) {
        self.totalPending = totalPending
        self.byType = byType
        self.byStatus = byStatus
        self.expiredCount = expiredCount
        self.almostTimeoutCount = almostTimeoutCount
    }
}
