//
//  CacheStaleGuard.swift
//  StorageKit
//
//  Stale cache forbidden for critical actions
//  Critical actions require fresh data
//

import Foundation
import WaanguCoreKit

/// Cache stale guard
/// Critical actions CANNOT use stale cache
public actor CacheStaleGuard {
    
    public static let shared = CacheStaleGuard()
    
    private var cacheEntries: [String: CacheEntry] = [:]
    
    private init() {}
    
    public struct CacheEntry: Sendable {
        public let key: String
        public let cachedAt: Date
        public let ttl: TimeInterval
        
        public init(key: String, cachedAt: Date, ttl: TimeInterval) {
            self.key = key
            self.cachedAt = cachedAt
            self.ttl = ttl
        }
        
        public var isStale: Bool {
            let elapsed = Date().timeIntervalSince(cachedAt)
            return elapsed > ttl
        }
    }
    
    public enum ActionType: String, Sendable {
        case payment
        case transfer
        case authentication
        case authorization
        case criticalAction
        case nonCritical
    }
    
    public enum CacheStaleError: Error, Sendable {
        case staleCacheForCriticalAction
        case cacheExpired
    }
    
    // MARK: - Public API
    
    /// Register cache entry
    public func registerCache(key: String, ttl: TimeInterval) {
        let entry = CacheEntry(
            key: key,
            cachedAt: Date(),
            ttl: ttl
        )
        
        cacheEntries[key] = entry
    }
    
    /// Validate cache for action (critical actions require fresh cache)
    public func validateCacheForAction(key: String, actionType: ActionType) throws {
        guard let entry = cacheEntries[key] else {
            return // No cache, will fetch fresh
        }
        
        // RULE: Critical actions cannot use stale cache
        if isCriticalAction(actionType) && entry.isStale {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: ["violation": "stale_cache_critical_action", "key": key, "action": actionType.rawValue]
                )
            }
            throw CacheStaleError.staleCacheForCriticalAction
        }
    }
    
    /// Check if action is critical
    public func isCriticalAction(_ actionType: ActionType) -> Bool {
        switch actionType {
        case .payment, .transfer, .authentication, .authorization, .criticalAction:
            return true
        case .nonCritical:
            return false
        }
    }
    
    /// Check if cache is stale
    public func isStale(key: String) -> Bool {
        return cacheEntries[key]?.isStale ?? true
    }
}
