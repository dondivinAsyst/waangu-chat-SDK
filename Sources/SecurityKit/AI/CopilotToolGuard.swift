//
//  CopilotToolGuard.swift
//  SecurityKit
//
//  RULE: Le mobile ne peut exécuter aucun Copilot tool seul
//  Copilot tools require approvalId + evidenceRefs + backend execution
//  No local execution allowed
//

import Foundation
import WaanguCoreKit

/// Copilot tool guard
/// RULE: Mobile cannot execute any Copilot tool alone
/// All tools require approvalId AND evidenceRefs AND backend execution
public actor CopilotToolGuard {
    
    public static let shared = CopilotToolGuard()
    
    private var backendExecutedTools: [String: BackendExecutedTool] = [:]
    private var attemptedLocalExecutions: [LocalExecutionAttempt] = []
    
    private init() {}
    
    public struct BackendExecutedTool: Sendable {
        public let toolId: String
        public let approvalId: String
        public let evidenceRefs: [String]
        public let backendSignature: String
        public let executedAt: Date
        public let executionResult: String
        
        public init(
            toolId: String,
            approvalId: String,
            evidenceRefs: [String],
            backendSignature: String,
            executedAt: Date,
            executionResult: String
        ) {
            self.toolId = toolId
            self.approvalId = approvalId
            self.evidenceRefs = evidenceRefs
            self.backendSignature = backendSignature
            self.executedAt = executedAt
            self.executionResult = executionResult
        }
    }
    
    public struct LocalExecutionAttempt: Sendable {
        public let toolId: String
        public let attemptedAt: Date
        public let stackTrace: String
        public let blocked: Bool
        
        public init(toolId: String, attemptedAt: Date, stackTrace: String, blocked: Bool) {
            self.toolId = toolId
            self.attemptedAt = attemptedAt
            self.stackTrace = stackTrace
            self.blocked = blocked
        }
    }
    
    public enum CopilotError: Error, Sendable, LocalizedError {
        case localExecutionForbidden
        case noApprovalId
        case noEvidenceRefs
        case insufficientEvidence
        case notBackendExecuted
        case invalidBackendSignature
        
        public var errorDescription: String? {
            switch self {
            case .localExecutionForbidden:
                return "Local Copilot tool execution is forbidden. Only backend can execute tools."
            case .noApprovalId:
                return "Copilot tool requires approvalId"
            case .noEvidenceRefs:
                return "Copilot tool requires evidenceRefs"
            case .insufficientEvidence:
                return "Insufficient evidence for tool execution"
            case .notBackendExecuted:
                return "Tool not executed by backend"
            case .invalidBackendSignature:
                return "Invalid backend signature on tool execution"
            }
        }
    }
    
    // MARK: - Public API
    
    /// Attempt to execute tool locally (ALWAYS FAILS)
    /// RULE: Mobile cannot execute any Copilot tool alone
    public func executeTool(
        toolId: String,
        approvalId: String?,
        evidenceRefs: [String]?,
        source: ExecutionSource
    ) throws {
        
        // Record attempt
        let attempt = LocalExecutionAttempt(
            toolId: toolId,
            attemptedAt: Date(),
            stackTrace: Thread.callStackSymbols.joined(separator: "\n"),
            blocked: true
        )
        attemptedLocalExecutions.append(attempt)
        
        // RULE: Only backend can execute
        guard source == .backend else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: [
                        "violation": "local_copilot_tool_execution_attempt",
                        "toolId": toolId,
                        "source": source.rawValue
                    ]
                )
            }
            throw CopilotError.localExecutionForbidden
        }
        
        // RULE: Must have approvalId
        guard let approvalId = approvalId, !approvalId.isEmpty else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: ["violation": "copilot_tool_no_approval", "toolId": toolId]
                )
            }
            throw CopilotError.noApprovalId
        }
        
        // RULE: Must have evidenceRefs
        guard let evidenceRefs = evidenceRefs, !evidenceRefs.isEmpty else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: ["violation": "copilot_tool_no_evidence", "toolId": toolId]
                )
            }
            throw CopilotError.noEvidenceRefs
        }
        
        throw CopilotError.localExecutionForbidden
    }
    
    /// Register backend-executed tool
    /// ONLY backend can call this through verified channel
    public func registerBackendExecution(
        toolId: String,
        approvalId: String,
        evidenceRefs: [String],
        backendSignature: String,
        executionResult: String,
        timestamp: Date
    ) throws {
        
        // Verify backend signature
        guard verifyBackendSignature(
            toolId: toolId,
            approvalId: approvalId,
            signature: backendSignature,
            timestamp: timestamp
        ) else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: [
                        "violation": "invalid_copilot_backend_signature",
                        "toolId": toolId
                    ]
                )
            }
            throw CopilotError.invalidBackendSignature
        }
        
        let executed = BackendExecutedTool(
            toolId: toolId,
            approvalId: approvalId,
            evidenceRefs: evidenceRefs,
            backendSignature: backendSignature,
            executedAt: timestamp,
            executionResult: executionResult
        )
        
        backendExecutedTools[toolId] = executed
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: [
                    "operation": "backend_copilot_tool_executed",
                    "toolId": toolId,
                    "approvalId": approvalId,
                    "evidenceCount": "\(evidenceRefs.count)"
                ]
            )
        }
    }
    
    /// Check if tool was backend-executed
    public func isBackendExecuted(toolId: String) -> Bool {
        return backendExecutedTools[toolId] != nil
    }
    
    /// Get backend-executed tool
    public func getBackendExecutedTool(toolId: String) -> BackendExecutedTool? {
        return backendExecutedTools[toolId]
    }
    
    /// Get blocked execution attempts
    public func getBlockedAttempts() -> [LocalExecutionAttempt] {
        return attemptedLocalExecutions
    }
    
    /// Get statistics
    public func getStatistics() -> CopilotStatistics {
        return CopilotStatistics(
            backendExecutedCount: backendExecutedTools.count,
            blockedAttemptsCount: attemptedLocalExecutions.count
        )
    }
    
    // MARK: - Private Helpers
    
    private func verifyBackendSignature(
        toolId: String,
        approvalId: String,
        signature: String,
        timestamp: Date
    ) -> Bool {
        // In production: HMAC-SHA256 with backend secret
        // Signature format: HMAC(toolId + approvalId + timestamp + secret)
        return !signature.isEmpty && signature.count >= 64
    }
}

// MARK: - Supporting Types

public enum ExecutionSource: String, Sendable {
    case backend
    case local
    case unknown
}

public struct CopilotStatistics: Sendable {
    public let backendExecutedCount: Int
    public let blockedAttemptsCount: Int
    
    public init(backendExecutedCount: Int, blockedAttemptsCount: Int) {
        self.backendExecutedCount = backendExecutedCount
        self.blockedAttemptsCount = blockedAttemptsCount
    }
}
