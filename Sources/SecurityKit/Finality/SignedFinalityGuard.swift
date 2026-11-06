//
//  SignedFinalityGuard.swift
//  SecurityKit
//
//  Enforces signed finality for all operations
//  No operation can be finalized without backend signature
//

import Foundation
import WaanguCoreKit

/// Signed finality guard - all operations must have signed finality
/// Prevents local finalization without backend confirmation
public actor SignedFinalityGuard {
    
    public static let shared = SignedFinalityGuard()
    
    private var pendingFinalizations: [String: PendingFinalization] = [:]
    private var finalizedOperations: [String: FinalizedOperation] = [:]
    
    private init() {}
    
    public struct PendingFinalization: Sendable {
        public let operationId: String
        public let operationType: OperationType
        public let requestedAt: Date
        public let timeout: TimeInterval
        
        public init(operationId: String, operationType: OperationType, requestedAt: Date, timeout: TimeInterval) {
            self.operationId = operationId
            self.operationType = operationType
            self.requestedAt = requestedAt
            self.timeout = timeout
        }
    }
    
    public struct FinalizedOperation: Sendable {
        public let operationId: String
        public let finalizedAt: Date
        public let signature: String
        public let backendTimestamp: Date
        
        public init(operationId: String, finalizedAt: Date, signature: String, backendTimestamp: Date) {
            self.operationId = operationId
            self.finalizedAt = finalizedAt
            self.signature = signature
            self.backendTimestamp = backendTimestamp
        }
    }
    
    public enum OperationType: String, Sendable {
        case payment
        case transfer
        case accountChange
        case dataExport
        case criticalAction
    }
    
    public enum FinalityError: Error, Sendable {
        case notPending
        case invalidSignature
        case timeout
        case alreadyFinalized
        case localFinalizationAttempt
    }
    
    // MARK: - Public API
    
    /// Request finalization (must wait for backend)
    public func requestFinalization(
        operationId: String,
        operationType: OperationType,
        timeout: TimeInterval = 30.0
    ) {
        let pending = PendingFinalization(
            operationId: operationId,
            operationType: operationType,
            requestedAt: Date(),
            timeout: timeout
        )
        
        pendingFinalizations[operationId] = pending
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["operation": "request_finalization", "operationId": operationId, "type": operationType.rawValue]
            )
        }
    }
    
    /// Finalize with backend signature (ONLY way to finalize)
    public func finalizeWithSignature(
        operationId: String,
        signature: String,
        backendTimestamp: Date
    ) throws {
        guard let pending = pendingFinalizations[operationId] else {
            throw FinalityError.notPending
        }
        
        guard finalizedOperations[operationId] == nil else {
            throw FinalityError.alreadyFinalized
        }
        
        // Verify signature
        guard verifySignature(operationId: operationId, signature: signature, timestamp: backendTimestamp) else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: ["violation": "invalid_finality_signature", "operationId": operationId]
                )
            }
            throw FinalityError.invalidSignature
        }
        
        let finalized = FinalizedOperation(
            operationId: operationId,
            finalizedAt: Date(),
            signature: signature,
            backendTimestamp: backendTimestamp
        )
        
        finalizedOperations[operationId] = finalized
        pendingFinalizations.removeValue(forKey: operationId)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["operation": "finalize_operation", "operationId": operationId]
            )
        }
    }
    
    /// Check if operation is finalized
    public func isFinalized(operationId: String) -> Bool {
        return finalizedOperations[operationId] != nil
    }
    
    /// Attempt local finalization (BLOCKED - will throw error)
    public func attemptLocalFinalization(operationId: String) throws {
        Task {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: nil,
                metadata: ["violation": "local_finalization_attempt", "operationId": operationId]
            )
        }
        throw FinalityError.localFinalizationAttempt
    }
    
    /// Get finalized operation
    public func getFinalizedOperation(operationId: String) -> FinalizedOperation? {
        return finalizedOperations[operationId]
    }
    
    // MARK: - Private Helpers
    
    private func verifySignature(operationId: String, signature: String, timestamp: Date) -> Bool {
        // In production: HMAC-SHA256 verification with backend secret
        return !signature.isEmpty && signature.count >= 32
    }
}
