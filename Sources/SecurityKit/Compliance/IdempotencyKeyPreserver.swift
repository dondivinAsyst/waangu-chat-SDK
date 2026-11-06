//
//  IdempotencyKeyPreserver.swift
//  SecurityKit
//
//  Retry operations preserve same idempotency key
//  Ensures retries use original key
//

import Foundation
import WaanguCoreKit

/// Idempotency key preserver
/// Retries MUST use same idempotency key
public actor IdempotencyKeyPreserver {
    
    public static let shared = IdempotencyKeyPreserver()
    
    private var operationKeys: [String: IdempotencyKey] = [:]
    
    private init() {}
    
    public struct IdempotencyKey: Sendable {
        public let operationId: String
        public let key: String
        public let createdAt: Date
        public let retryCount: Int
        
        public init(operationId: String, key: String, createdAt: Date, retryCount: Int) {
            self.operationId = operationId
            self.key = key
            self.createdAt = createdAt
            self.retryCount = retryCount
        }
    }
    
    public enum KeyPreservationError: Error, Sendable {
        case keyMismatch
        case keyNotFound
    }
    
    // MARK: - Public API
    
    /// Register operation with idempotency key
    public func registerOperation(operationId: String, key: String) {
        let idempotencyKey = IdempotencyKey(
            operationId: operationId,
            key: key,
            createdAt: Date(),
            retryCount: 0
        )
        
        operationKeys[operationId] = idempotencyKey
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["operation": "register_idempotency_key", "operationId": operationId]
            )
        }
    }
    
    /// Retry operation (MUST use same key)
    public func retryOperation(operationId: String, providedKey: String) throws {
        guard let storedKey = operationKeys[operationId] else {
            throw KeyPreservationError.keyNotFound
        }
        
        // RULE: Retry MUST use same idempotency key
        guard storedKey.key == providedKey else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: ["violation": "idempotency_key_mismatch", "operationId": operationId]
                )
            }
            throw KeyPreservationError.keyMismatch
        }
        
        // Update retry count
        let updated = IdempotencyKey(
            operationId: storedKey.operationId,
            key: storedKey.key,
            createdAt: storedKey.createdAt,
            retryCount: storedKey.retryCount + 1
        )
        
        operationKeys[operationId] = updated
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["operation": "retry_with_same_key", "operationId": operationId, "retryCount": "\(updated.retryCount)"]
            )
        }
    }
    
    /// Get idempotency key
    public func getKey(operationId: String) -> String? {
        return operationKeys[operationId]?.key
    }
}
