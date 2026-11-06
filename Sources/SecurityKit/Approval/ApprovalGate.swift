//
//  ApprovalGate.swift
//  CoreKit
//
//  Blocking approval gates for critical operations
//  RULE: ApprovalRequired bloquant

import Foundation
import WaanguCoreKit

public actor ApprovalGate {
    
    public static let shared = ApprovalGate()
    
    private var pendingApprovals: [String: PendingApproval] = [:]
    private var approvalHistory: [ApprovalRecord] = []
    
    private init() {}
    
    // MARK: - Approval Gate
    
    /// Requests approval for critical operation (BLOCKING)
    /// RULE: ApprovalRequired bloquant
    public func requestApproval(
        operationId: String,
        operationType: OperationType,
        description: String,
        requester: String,
        metadata: [String: String] = [:]
    ) async throws {
        
        let approval = PendingApproval(
            operationId: operationId,
            operationType: operationType,
            description: description,
            requester: requester,
            metadata: metadata,
            requestedAt: Date(),
            status: .pending
        )
        
        pendingApprovals[operationId] = approval
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "approval_requested",
                "operation_id": operationId,
                "operation_type": operationType.rawValue,
                "requester": requester
            ],
            severity: .warning
        )
        
        // BLOCKING: Wait for approval
        try await waitForApproval(operationId: operationId)
    }
    
    /// Waits for approval (BLOCKING)
    private func waitForApproval(operationId: String) async throws {
        
        let timeout: TimeInterval = 300 // 5 minutes
        let startTime = Date()
        
        while true {
            guard let approval = pendingApprovals[operationId] else {
                throw ApprovalError.approvalNotFound(operationId: operationId)
            }
            
            switch approval.status {
            case .approved:
                return
                
            case .rejected:
                throw ApprovalError.approvalRejected(
                    operationId: operationId,
                    reason: approval.rejectionReason ?? "No reason provided"
                )
                
            case .pending:
                // Check timeout
                if Date().timeIntervalSince(startTime) > timeout {
                    throw ApprovalError.approvalTimeout(operationId: operationId)
                }
                
                // Wait and check again
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }
    
    /// Approves pending operation
    public func approve(
        operationId: String,
        approver: String,
        comments: String? = nil
    ) async throws {
        
        guard var approval = pendingApprovals[operationId] else {
            throw ApprovalError.approvalNotFound(operationId: operationId)
        }
        
        approval.status = .approved
        approval.approver = approver
        approval.approvedAt = Date()
        approval.comments = comments
        
        pendingApprovals[operationId] = approval
        
        // Record in history
        let record = ApprovalRecord(
            operationId: operationId,
            operationType: approval.operationType,
            requester: approval.requester,
            approver: approver,
            status: .approved,
            requestedAt: approval.requestedAt,
            resolvedAt: Date(),
            comments: comments
        )
        
        approvalHistory.append(record)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "approval_granted",
                "operation_id": operationId,
                "approver": approver
            ],
            severity: .info
        )
    }
    
    /// Rejects pending operation
    public func reject(
        operationId: String,
        approver: String,
        reason: String
    ) async throws {
        
        guard var approval = pendingApprovals[operationId] else {
            throw ApprovalError.approvalNotFound(operationId: operationId)
        }
        
        approval.status = .rejected
        approval.approver = approver
        approval.rejectionReason = reason
        approval.approvedAt = Date()
        
        pendingApprovals[operationId] = approval
        
        // Record in history
        let record = ApprovalRecord(
            operationId: operationId,
            operationType: approval.operationType,
            requester: approval.requester,
            approver: approver,
            status: .rejected,
            requestedAt: approval.requestedAt,
            resolvedAt: Date(),
            comments: reason
        )
        
        approvalHistory.append(record)
        
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: approval.requester,
            metadata: [
                "action": "approval_rejected",
                "operation_id": operationId,
                "approver": approver,
                "reason": reason
            ]
        )
    }
    
    /// Gets pending approvals
    public func getPendingApprovals() -> [PendingApproval] {
        Array(pendingApprovals.values.filter { $0.status == .pending })
    }
    
    /// Gets approval history
    public func getApprovalHistory(limit: Int = 100) -> [ApprovalRecord] {
        Array(approvalHistory.prefix(limit))
    }
    
    // MARK: - Types
    
    public struct PendingApproval {
        public let operationId: String
        public let operationType: OperationType
        public let description: String
        public let requester: String
        public let metadata: [String: String]
        public let requestedAt: Date
        public var status: ApprovalStatus
        public var approver: String?
        public var approvedAt: Date?
        public var rejectionReason: String?
        public var comments: String?
    }
    
    public struct ApprovalRecord {
        public let operationId: String
        public let operationType: OperationType
        public let requester: String
        public let approver: String
        public let status: ApprovalStatus
        public let requestedAt: Date
        public let resolvedAt: Date
        public let comments: String?
    }
    
    public enum OperationType: String {
        case dataExport
        case accountDeletion
        case privilegeEscalation
        case configurationChange
        case securityPolicyChange
        case paymentRefund
        case userBan
        case dataAccess
    }
    
    public enum ApprovalStatus: String {
        case pending
        case approved
        case rejected
    }
    
    public enum ApprovalError: Error, LocalizedError {
        case approvalNotFound(operationId: String)
        case approvalRejected(operationId: String, reason: String)
        case approvalTimeout(operationId: String)
        
        public var errorDescription: String? {
            switch self {
            case .approvalNotFound(let operationId):
                return "Approval not found: \(operationId)"
            case .approvalRejected(let operationId, let reason):
                return "Approval rejected for \(operationId): \(reason)"
            case .approvalTimeout(let operationId):
                return "Approval timeout for \(operationId)"
            }
        }
    }
}
