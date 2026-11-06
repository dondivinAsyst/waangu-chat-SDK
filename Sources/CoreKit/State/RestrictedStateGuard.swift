//
//  RestrictedStateGuard.swift
//  CoreKit
//
//  Makes restricted states visible and enforced
//  Ensures operations in restricted mode are properly blocked
//

import Foundation

/// Guards and enforces restricted states
/// Makes restrictions visible to users and system
public actor RestrictedStateGuard {
    
    public static let shared = RestrictedStateGuard()
    
    private var restrictions: [String: Restriction] = [:]
    private var globalRestrictions: Set<RestrictionType> = []
    private var observers: [UUID: @Sendable (Restriction) -> Void] = [:]
    
    private init() {}
    
    public struct Restriction: Sendable {
        public let id: String
        public let type: RestrictionType
        public let reason: String
        public let appliedAt: Date
        public let expiresAt: Date?
        public let metadata: [String: String]
        
        public init(id: String, type: RestrictionType, reason: String, appliedAt: Date, expiresAt: Date?, metadata: [String: String]) {
            self.id = id
            self.type = type
            self.reason = reason
            self.appliedAt = appliedAt
            self.expiresAt = expiresAt
            self.metadata = metadata
        }
        
        public var isExpired: Bool {
            guard let expiresAt = expiresAt else { return false }
            return Date() > expiresAt
        }
        
        public var isActive: Bool {
            return !isExpired
        }
    }
    
    public enum RestrictionType: String, Sendable, CaseIterable {
        case payment
        case messaging
        case fileUpload
        case voiceCall
        case videoCall
        case groupCreation
        case contactAdd
        case profileEdit
        case settingsChange
        case dataExport
        case accountDeletion
        case all
    }
    
    public enum RestrictionError: Error, Sendable {
        case restricted(type: RestrictionType, reason: String)
        case globallyRestricted(type: RestrictionType)
        case notFound
    }
    
    // MARK: - Public API
    
    /// Apply a restriction
    public func applyRestriction(
        id: String,
        type: RestrictionType,
        reason: String,
        duration: TimeInterval? = nil,
        metadata: [String: String] = [:]
    ) {
        let expiresAt = duration.map { Date().addingTimeInterval($0) }
        
        let restriction = Restriction(
            id: id,
            type: type,
            reason: reason,
            appliedAt: Date(),
            expiresAt: expiresAt,
            metadata: metadata
        )
        
        restrictions[id] = restriction
        notifyObservers(restriction)
        
        Task {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: metadata["userId"],
                metadata: [
                    "operation": "apply_restriction",
                    "id": id,
                    "type": type.rawValue,
                    "reason": reason
                ]
            )
        }
    }
    
    /// Apply global restriction
    public func applyGlobalRestriction(type: RestrictionType, reason: String) {
        globalRestrictions.insert(type)
        
        Task {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: nil,
                metadata: [
                    "operation": "apply_global_restriction",
                    "type": type.rawValue,
                    "reason": reason
                ]
            )
        }
    }
    
    /// Remove restriction
    public func removeRestriction(id: String) throws {
        guard restrictions[id] != nil else {
            throw RestrictionError.notFound
        }
        
        restrictions.removeValue(forKey: id)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["operation": "remove_restriction", "id": id]
            )
        }
    }
    
    /// Remove global restriction
    public func removeGlobalRestriction(type: RestrictionType) {
        globalRestrictions.remove(type)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["operation": "remove_global_restriction", "type": type.rawValue]
            )
        }
    }
    
    /// Check if operation is restricted
    public func isRestricted(type: RestrictionType, userId: String? = nil) -> Bool {
        // Check global restrictions
        if globalRestrictions.contains(type) || globalRestrictions.contains(.all) {
            return true
        }
        
        // Check user-specific restrictions
        let activeRestrictions = restrictions.values.filter { $0.isActive }
        
        for restriction in activeRestrictions {
            if restriction.type == type || restriction.type == .all {
                if let userId = userId, let restrictedUserId = restriction.metadata["userId"] {
                    if restrictedUserId == userId {
                        return true
                    }
                } else if userId == nil {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Validate operation is allowed
    public func validateOperation(type: RestrictionType, userId: String? = nil) throws {
        // Check global restrictions
        if globalRestrictions.contains(type) {
            throw RestrictionError.globallyRestricted(type: type)
        }
        
        if globalRestrictions.contains(.all) {
            throw RestrictionError.globallyRestricted(type: .all)
        }
        
        // Check user-specific restrictions
        let activeRestrictions = restrictions.values.filter { $0.isActive }
        
        for restriction in activeRestrictions {
            if restriction.type == type || restriction.type == .all {
                if let userId = userId, let restrictedUserId = restriction.metadata["userId"] {
                    if restrictedUserId == userId {
                        throw RestrictionError.restricted(type: type, reason: restriction.reason)
                    }
                } else if userId == nil {
                    throw RestrictionError.restricted(type: type, reason: restriction.reason)
                }
            }
        }
    }
    
    /// Get active restrictions
    public func getActiveRestrictions() -> [Restriction] {
        return restrictions.values.filter { $0.isActive }
    }
    
    /// Get restrictions by type
    public func getRestrictionsByType(_ type: RestrictionType) -> [Restriction] {
        return restrictions.values.filter { $0.type == type && $0.isActive }
    }
    
    /// Get restrictions for user
    public func getRestrictionsForUser(_ userId: String) -> [Restriction] {
        return restrictions.values.filter {
            $0.isActive && $0.metadata["userId"] == userId
        }
    }
    
    /// Get global restrictions
    public func getGlobalRestrictions() -> Set<RestrictionType> {
        return globalRestrictions
    }
    
    /// Clean up expired restrictions
    public func cleanupExpired() -> [String] {
        let expired = restrictions.values.filter { $0.isExpired }
        let expiredIds = expired.map { $0.id }
        
        for id in expiredIds {
            restrictions.removeValue(forKey: id)
        }
        
        return expiredIds
    }
    
    /// Add observer for restrictions
    public func addObserver(_ observer: @escaping @Sendable (Restriction) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }
    
    /// Remove observer
    public func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
    
    /// Get statistics
    public func getStatistics() -> RestrictionStatistics {
        let active = getActiveRestrictions()
        let byType = Dictionary(grouping: active, by: { $0.type })
        
        return RestrictionStatistics(
            totalActive: active.count,
            byType: byType.mapValues { $0.count },
            globalCount: globalRestrictions.count,
            expiredCount: restrictions.values.filter { $0.isExpired }.count
        )
    }
    
    // MARK: - Private Helpers
    
    private func notifyObservers(_ restriction: Restriction) {
        for observer in observers.values {
            observer(restriction)
        }
    }
}

// MARK: - Supporting Types

public struct RestrictionStatistics: Sendable {
    public let totalActive: Int
    public let byType: [RestrictedStateGuard.RestrictionType: Int]
    public let globalCount: Int
    public let expiredCount: Int
    
    public init(totalActive: Int, byType: [RestrictedStateGuard.RestrictionType: Int], globalCount: Int, expiredCount: Int) {
        self.totalActive = totalActive
        self.byType = byType
        self.globalCount = globalCount
        self.expiredCount = expiredCount
    }
}
