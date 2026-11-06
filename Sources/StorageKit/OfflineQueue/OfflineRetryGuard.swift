//
//  OfflineRetryGuard.swift
//  StorageKit
//
//  Ensures offline retry never finalizes without CoreAck
//  All retries must wait for backend acknowledgment
//

import Foundation
import WaanguCoreKit

/// Offline retry guard - never finalizes without CoreAck
/// Prevents premature finalization of offline operations
public actor OfflineRetryGuard {

    public static let shared = OfflineRetryGuard()

    private var retryingOperations: [String: RetryingOperation] = [:]
    private var acknowledgedOperations: Set<String> = []

    private init() {}

    public struct RetryingOperation: Sendable {
        public let operationId: String
        public let attemptCount: Int
        public let lastAttemptAt: Date
        public let maxAttempts: Int
        public let waitingForCoreAck: Bool

        public init(operationId: String, attemptCount: Int, lastAttemptAt: Date, maxAttempts: Int, waitingForCoreAck: Bool) {
            self.operationId = operationId
            self.attemptCount = attemptCount
            self.lastAttemptAt = lastAttemptAt
            self.maxAttempts = maxAttempts
            self.waitingForCoreAck = waitingForCoreAck
        }
    }

    public enum RetryError: Error, Sendable {
        case maxAttemptsReached
        case waitingForAck
        case noCoreAck
        case prematureFinalization
    }

    // MARK: - Public API

    /// Register retry operation
    public func registerRetry(operationId: String, maxAttempts: Int = 5) {
        let operation = RetryingOperation(
            operationId: operationId,
            attemptCount: 0,
            lastAttemptAt: Date(),
            maxAttempts: maxAttempts,
            waitingForCoreAck: true
        )

        retryingOperations[operationId] = operation

        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "register_retry", "operationId": operationId]
            )
        }
    }

    /// Attempt retry (must wait for CoreAck)
    public func attemptRetry(operationId: String) throws {
        guard var operation = retryingOperations[operationId] else {
            return
        }

        guard !operation.waitingForCoreAck else {
            throw RetryError.waitingForAck
        }

        guard operation.attemptCount < operation.maxAttempts else {
            throw RetryError.maxAttemptsReached
        }

        operation = RetryingOperation(
            operationId: operation.operationId,
            attemptCount: operation.attemptCount + 1,
            lastAttemptAt: Date(),
            maxAttempts: operation.maxAttempts,
            waitingForCoreAck: true
        )

        retryingOperations[operationId] = operation

        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "retry_attempt", "operationId": operationId, "attempt": "\(operation.attemptCount)"]
            )
        }
    }

    /// Receive CoreAck (REQUIRED for finalization)
    public func receiveCoreAck(operationId: String, ackSignature: String) {
        guard var operation = retryingOperations[operationId] else {
            return
        }

        operation = RetryingOperation(
            operationId: operation.operationId,
            attemptCount: operation.attemptCount,
            lastAttemptAt: operation.lastAttemptAt,
            maxAttempts: operation.maxAttempts,
            waitingForCoreAck: false
        )

        retryingOperations[operationId] = operation
        acknowledgedOperations.insert(operationId)

        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "core_ack_received", "operationId": operationId]
            )
        }
    }

    /// Finalize operation (ONLY if CoreAck received)
    public func finalizeOperation(operationId: String) throws {
        guard let operation = retryingOperations[operationId] else {
            return
        }

        guard !operation.waitingForCoreAck else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: ["violation": "finalize_without_core_ack", "operationId": operationId]
                )
            }
            throw RetryError.noCoreAck
        }

        guard acknowledgedOperations.contains(operationId) else {
            throw RetryError.noCoreAck
        }

        retryingOperations.removeValue(forKey: operationId)

        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "finalize_retry", "operationId": operationId]
            )
        }
    }

    /// Check if waiting for CoreAck
    public func isWaitingForAck(operationId: String) -> Bool {
        return retryingOperations[operationId]?.waitingForCoreAck ?? false
    }
}
