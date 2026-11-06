import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Audit trail system for tracking user actions and system events
/// Provides compliance-ready logging with structured data
public actor AuditBreadcrumb {
    
    public static let shared = AuditBreadcrumb()
    
    private var breadcrumbs: [AuditEntry] = []
    private let maxBreadcrumbs: Int
    private let fileManager = FileManager.default
    private let auditDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var observers: [UUID: @Sendable (AuditEntry) async -> Void] = [:]
    
    private init(maxBreadcrumbs: Int = 1000) {
        self.maxBreadcrumbs = maxBreadcrumbs
        
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.auditDirectory = documentsPath.appendingPathComponent("AuditTrail", isDirectory: true)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: auditDirectory, withIntermediateDirectories: true)
        
        // Configure encoder
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Public API
    
    /// Record an audit entry
    public func record(
        action: AuditAction,
        category: AuditCategory,
        userId: String? = nil,
        metadata: [String: String] = [:],
        severity: AuditSeverity = .info
    ) async {
        let entry = AuditEntry(
            id: UUID().lowercasedString,
            timestamp: Date(),
            action: action,
            category: category,
            userId: userId,
            metadata: metadata,
            severity: severity,
            deviceInfo: await collectDeviceInfo()
        )
        
        // Add to in-memory breadcrumbs
        breadcrumbs.append(entry)
        
        // Trim if needed
        if breadcrumbs.count > maxBreadcrumbs {
            breadcrumbs.removeFirst(breadcrumbs.count - maxBreadcrumbs)
        }
        
        // Persist critical entries
        if severity == .critical || severity == .high {
            try? await persist(entry)
        }
        
        // Notify observers
        await notifyObservers(entry)
    }
    
    /// Get recent breadcrumbs
    public func getRecent(limit: Int = 100) -> [AuditEntry] {
        Array(breadcrumbs.suffix(limit))
    }
    
    /// Get breadcrumbs by category
    public func get(category: AuditCategory, limit: Int = 100) -> [AuditEntry] {
        breadcrumbs
            .filter { $0.category == category }
            .suffix(limit)
            .map { $0 }
    }
    
    /// Get breadcrumbs by user
    public func get(userId: String, limit: Int = 100) -> [AuditEntry] {
        breadcrumbs
            .filter { $0.userId == userId }
            .suffix(limit)
            .map { $0 }
    }
    
    /// Get breadcrumbs by severity
    public func get(severity: AuditSeverity, limit: Int = 100) -> [AuditEntry] {
        breadcrumbs
            .filter { $0.severity == severity }
            .suffix(limit)
            .map { $0 }
    }
    
    /// Get breadcrumbs in time range
    public func get(from: Date, to: Date) -> [AuditEntry] {
        breadcrumbs.filter { entry in
            entry.timestamp >= from && entry.timestamp <= to
        }
    }
    
    /// Search breadcrumbs
    public func search(query: String) -> [AuditEntry] {
        let lowercased = query.lowercased()
        return breadcrumbs.filter { entry in
            entry.action.rawValue.lowercased().contains(lowercased) ||
            entry.category.rawValue.lowercased().contains(lowercased) ||
            entry.metadata.values.contains { $0.lowercased().contains(lowercased) }
        }
    }
    
    /// Export audit trail to file
    public func export(from: Date? = nil, to: Date? = nil) async throws -> URL {
        let entries: [AuditEntry]
        
        if let from = from, let to = to {
            entries = get(from: from, to: to)
        } else {
            entries = breadcrumbs
        }
        
        let data = try encoder.encode(entries)
        
        let filename = "audit_trail_\(ISO8601DateFormatter().string(from: Date())).json"
        let fileURL = auditDirectory.appendingPathComponent(filename)
        
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
    
    /// Clear in-memory breadcrumbs
    public func clear() {
        breadcrumbs.removeAll()
    }
    
    /// Get audit statistics
    public func getStats() -> AuditStats {
        let byCategory = Dictionary(grouping: breadcrumbs) { $0.category }
        let bySeverity = Dictionary(grouping: breadcrumbs) { $0.severity }
        let byUser = Dictionary(grouping: breadcrumbs) { $0.userId ?? "anonymous" }
        
        return AuditStats(
            totalEntries: breadcrumbs.count,
            entriesByCategory: byCategory.mapValues { $0.count },
            entriesBySeverity: bySeverity.mapValues { $0.count },
            entriesByUser: byUser.mapValues { $0.count },
            oldestEntry: breadcrumbs.first?.timestamp,
            newestEntry: breadcrumbs.last?.timestamp
        )
    }
    
    // MARK: - Observers
    
    /// Add observer for audit entries
    public func addObserver(_ observer: @escaping @Sendable (AuditEntry) async -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }
    
    /// Remove observer
    public func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }
    
    // MARK: - Private Helpers
    
    private func persist(_ entry: AuditEntry) async throws {
        let filename = "\(entry.id).json"
        let fileURL = auditDirectory.appendingPathComponent(filename)
        let data = try encoder.encode(entry)
        try data.write(to: fileURL, options: .atomic)
    }
    
    private func collectDeviceInfo() async -> DeviceInfo {
        #if canImport(UIKit)
        DeviceInfo(
            deviceModel: await UIDevice.current.model,
            systemVersion: await UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        )
        #else
        DeviceInfo(
            deviceModel: "Mac",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        )
        #endif
    }
    
    private func notifyObservers(_ entry: AuditEntry) async {
        for observer in observers.values {
            await observer(entry)
        }
    }
}

// MARK: - Models

/// Audit entry
public struct AuditEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let action: AuditAction
    public let category: AuditCategory
    public let userId: String?
    public let metadata: [String: String]
    public let severity: AuditSeverity
    public let deviceInfo: DeviceInfo
}

/// Audit action types
public enum AuditAction: String, Codable, Sendable {
    // Authentication
    case login = "LOGIN"
    case logout = "LOGOUT"
    case loginFailed = "LOGIN_FAILED"
    case tokenRefresh = "TOKEN_REFRESH"
    case biometricAuth = "BIOMETRIC_AUTH"
    
    // User actions
    case messageSent = "MESSAGE_SENT"
    case messageDeleted = "MESSAGE_DELETED"
    case messageEdited = "MESSAGE_EDITED"
    case fileUploaded = "FILE_UPLOADED"
    case fileDownloaded = "FILE_DOWNLOADED"
    case profileUpdated = "PROFILE_UPDATED"
    case settingsChanged = "SETTINGS_CHANGED"
    
    // Data access
    case dataViewed = "DATA_VIEWED"
    case dataExported = "DATA_EXPORTED"
    case dataDeleted = "DATA_DELETED"
    
    // Security
    case permissionGranted = "PERMISSION_GRANTED"
    case permissionDenied = "PERMISSION_DENIED"
    case securityViolation = "SECURITY_VIOLATION"
    case deviceCompromised = "DEVICE_COMPROMISED"
    
    // System
    case appLaunched = "APP_LAUNCHED"
    case appTerminated = "APP_TERMINATED"
    case appBackgrounded = "APP_BACKGROUNDED"
    case appForegrounded = "APP_FOREGROUNDED"
    case errorOccurred = "ERROR_OCCURRED"
    case crashDetected = "CRASH_DETECTED"
    
    // Network
    case apiCallMade = "API_CALL_MADE"
    case apiCallFailed = "API_CALL_FAILED"
    case offlineMode = "OFFLINE_MODE"
    case onlineMode = "ONLINE_MODE"
}

/// Audit category
public enum AuditCategory: String, Codable, Sendable {
    case authentication = "AUTHENTICATION"
    case authorization = "AUTHORIZATION"
    case dataAccess = "DATA_ACCESS"
    case dataModification = "DATA_MODIFICATION"
    case security = "SECURITY"
    case system = "SYSTEM"
    case network = "NETWORK"
    case user = "USER"
}

/// Audit severity
public enum AuditSeverity: String, Codable, Sendable, Comparable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case high = "HIGH"
    case critical = "CRITICAL"
    
    public static func < (lhs: AuditSeverity, rhs: AuditSeverity) -> Bool {
        let order: [AuditSeverity] = [.debug, .info, .warning, .high, .critical]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// Device information
public struct DeviceInfo: Codable, Sendable {
    public let deviceModel: String
    public let systemVersion: String
    public let appVersion: String
    public let buildNumber: String
}

/// Audit statistics
public struct AuditStats: Sendable {
    public let totalEntries: Int
    public let entriesByCategory: [AuditCategory: Int]
    public let entriesBySeverity: [AuditSeverity: Int]
    public let entriesByUser: [String: Int]
    public let oldestEntry: Date?
    public let newestEntry: Date?
}

// MARK: - Convenience Extensions

public extension AuditBreadcrumb {
    /// Record authentication event
    func recordAuth(
        action: AuditAction,
        userId: String?,
        success: Bool,
        metadata: [String: String] = [:]
    ) async {
        var fullMetadata = metadata
        fullMetadata["success"] = String(success)
        
        await record(
            action: action,
            category: .authentication,
            userId: userId,
            metadata: fullMetadata,
            severity: success ? .info : .warning
        )
    }
    
    /// Record security event
    func recordSecurity(
        action: AuditAction,
        userId: String?,
        metadata: [String: String] = [:]
    ) async {
        await record(
            action: action,
            category: .security,
            userId: userId,
            metadata: metadata,
            severity: .high
        )
    }
    
    /// Record data access
    func recordDataAccess(
        action: AuditAction,
        userId: String?,
        resourceType: String,
        resourceId: String,
        metadata: [String: String] = [:]
    ) async {
        var fullMetadata = metadata
        fullMetadata["resource_type"] = resourceType
        fullMetadata["resource_id"] = resourceId
        
        await record(
            action: action,
            category: .dataAccess,
            userId: userId,
            metadata: fullMetadata,
            severity: .info
        )
    }
}

// MARK: - Usage Examples

/*
 Example 1: Record user login
 
 await AuditBreadcrumb.shared.recordAuth(
     action: .login,
     userId: "user_123",
     success: true,
     metadata: ["method": "biometric"]
 )
 
 Example 2: Record message sent
 
 await AuditBreadcrumb.shared.record(
     action: .messageSent,
     category: .user,
     userId: "user_123",
     metadata: [
         "message_id": "msg_456",
         "recipient_id": "user_789",
         "message_type": "text"
     ],
     severity: .info
 )
 
 Example 3: Record security violation
 
 await AuditBreadcrumb.shared.recordSecurity(
     action: .securityViolation,
     userId: "user_123",
     metadata: [
         "violation_type": "jailbreak_detected",
         "device_trust_level": "compromised"
     ]
 )
 
 Example 4: Get recent audit entries
 
 let recent = await AuditBreadcrumb.shared.getRecent(limit: 50)
 for entry in recent {
     print("\(entry.timestamp): \(entry.action.rawValue)")
 }
 
 Example 5: Export audit trail
 
 let fileURL = try await AuditBreadcrumb.shared.export(
     from: Date().addingTimeInterval(-86400), // Last 24 hours
     to: Date()
 )
 print("Audit trail exported to: \(fileURL)")
 
 Example 6: Monitor audit events
 
 let observerId = await AuditBreadcrumb.shared.addObserver { entry in
     if entry.severity >= .high {
         // Send to monitoring service
         await monitoringService.alert(entry)
     }
 }
 */
