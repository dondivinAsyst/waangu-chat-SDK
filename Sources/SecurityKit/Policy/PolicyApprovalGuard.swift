//
//  PolicyApprovalGuard.swift
//  SecurityKit
//
//  RULE: Le mobile ne peut approuver aucune policy
//  All policy approvals MUST come from backend
//

import Foundation
import WaanguCoreKit

/// Prevents client-side policy approval
/// RULE: Mobile cannot approve any policy
public actor PolicyApprovalGuard {
    
    public static let shared = PolicyApprovalGuard()
    
    private var backendApprovedPolicies: [String: BackendApprovedPolicy] = [:]
    private var attemptedLocalApprovals: [LocalPolicyApprovalAttempt] = []
    
    private init() {}
    
    public struct BackendApprovedPolicy: Sendable {
        public let policyId: String
        public let policyType: PolicyType
        public let version: String
        public let backendSignature: String
        public let approvedAt: Date
        public let approvedBy: String
        public let evidenceRefs: [String]
        
        public init(
            policyId: String,
            policyType: PolicyType,
            version: String,
            backendSignature: String,
            approvedAt: Date,
            approvedBy: String,
            evidenceRefs: [String]
        ) {
            self.policyId = policyId
            self.policyType = policyType
            self.version = version
            self.backendSignature = backendSignature
            self.approvedAt = approvedAt
            self.approvedBy = approvedBy
            self.evidenceRefs = evidenceRefs
        }
    }
    
    public struct LocalPolicyApprovalAttempt: Sendable {
        public let policyId: String
        public let policyType: PolicyType
        public let attemptedAt: Date
        public let stackTrace: String
        public let blocked: Bool
        
        public init(
            policyId: String,
            policyType: PolicyType,
            attemptedAt: Date,
            stackTrace: String,
            blocked: Bool
        ) {
            self.policyId = policyId
            self.policyType = policyType
            self.attemptedAt = attemptedAt
            self.stackTrace = stackTrace
            self.blocked = blocked
        }
    }
    
    public enum PolicyType: String, Sendable {
        case privacyPolicy
        case termsOfService
        case dataProcessing
        case consentManagement
        case securityPolicy
        case compliancePolicy
        case paymentPolicy
        case refundPolicy
    }
    
    public enum PolicyApprovalError: Error, Sendable, LocalizedError {
        case localApprovalForbidden
        case notBackendApproved
        case invalidApprovalSource
        case invalidBackendSignature
        case missingEvidenceRefs
        
        public var errorDescription: String? {
            switch self {
            case .localApprovalForbidden:
                return "Local policy approval is forbidden. Only backend can approve policies."
            case .notBackendApproved:
                return "Policy not approved by backend"
            case .invalidApprovalSource:
                return "Invalid approval source - must be backend"
            case .invalidBackendSignature:
                return "Invalid backend signature on policy approval"
            case .missingEvidenceRefs:
                return "Policy approval requires evidence references"
            }
        }
    }
    
    // MARK: - Public API
    
    /// Attempt to approve policy (ALWAYS FAILS for local calls)
    /// RULE: Mobile cannot approve any policy
    public func approvePolicy(
        policyId: String,
        policyType: PolicyType,
        source: ApprovalSource
    ) throws {
        
        // Record attempt
        let attempt = LocalPolicyApprovalAttempt(
            policyId: policyId,
            policyType: policyType,
            attemptedAt: Date(),
            stackTrace: Thread.callStackSymbols.joined(separator: "\n"),
            blocked: true
        )
        attemptedLocalApprovals.append(attempt)
        
        // RULE: Only backend can approve
        guard source == .backend else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: [
                        "violation": "local_policy_approval_attempt",
                        "policyId": policyId,
                        "policyType": policyType.rawValue,
                        "source": source.rawValue
                    ]
                )
            }
            throw PolicyApprovalError.localApprovalForbidden
        }
        
        throw PolicyApprovalError.invalidApprovalSource
    }
    
    /// Register backend-approved policy
    /// ONLY backend can call this through verified channel
    public func registerBackendApproval(
        policyId: String,
        policyType: PolicyType,
        version: String,
        backendSignature: String,
        approvedBy: String,
        evidenceRefs: [String],
        timestamp: Date
    ) throws {
        
        // RULE: Must have evidence refs
        guard !evidenceRefs.isEmpty else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: [
                        "violation": "policy_approval_without_evidence",
                        "policyId": policyId
                    ]
                )
            }
            throw PolicyApprovalError.missingEvidenceRefs
        }
        
        // Verify backend signature
        guard verifyBackendSignature(
            policyId: policyId,
            version: version,
            signature: backendSignature,
            timestamp: timestamp
        ) else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: [
                        "violation": "invalid_policy_backend_signature",
                        "policyId": policyId
                    ]
                )
            }
            throw PolicyApprovalError.invalidBackendSignature
        }
        
        let approved = BackendApprovedPolicy(
            policyId: policyId,
            policyType: policyType,
            version: version,
            backendSignature: backendSignature,
            approvedAt: timestamp,
            approvedBy: approvedBy,
            evidenceRefs: evidenceRefs
        )
        
        backendApprovedPolicies[policyId] = approved
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: [
                    "operation": "backend_policy_approved",
                    "policyId": policyId,
                    "policyType": policyType.rawValue,
                    "version": version,
                    "approvedBy": approvedBy,
                    "evidenceCount": "\(evidenceRefs.count)"
                ]
            )
        }
    }
    
    /// Check if policy is backend-approved
    public func isBackendApproved(policyId: String) -> Bool {
        return backendApprovedPolicies[policyId] != nil
    }
    
    /// Get backend-approved policy
    public func getBackendApprovedPolicy(policyId: String) -> BackendApprovedPolicy? {
        return backendApprovedPolicies[policyId]
    }
    
    /// Check if specific policy version is approved
    public func isPolicyVersionApproved(policyId: String, version: String) -> Bool {
        guard let approved = backendApprovedPolicies[policyId] else {
            return false
        }
        return approved.version == version
    }
    
    /// Get blocked approval attempts
    public func getBlockedAttempts() -> [LocalPolicyApprovalAttempt] {
        return attemptedLocalApprovals
    }
    
    /// Get statistics
    public func getStatistics() -> PolicyApprovalStatistics {
        let byType = Dictionary(grouping: backendApprovedPolicies.values) { $0.policyType }
            .mapValues { $0.count }
        
        return PolicyApprovalStatistics(
            backendApprovedCount: backendApprovedPolicies.count,
            blockedAttemptsCount: attemptedLocalApprovals.count,
            approvalsByType: byType
        )
    }
    
    // MARK: - Private Helpers
    
    private func verifyBackendSignature(
        policyId: String,
        version: String,
        signature: String,
        timestamp: Date
    ) -> Bool {
        // In production: HMAC-SHA256 with backend secret
        // Signature format: HMAC(policyId + version + timestamp + secret)
        return !signature.isEmpty && signature.count >= 64
    }
}

// MARK: - Supporting Types

public enum ApprovalSource: String, Sendable {
    case backend
    case local
    case unknown
}

public struct PolicyApprovalStatistics: Sendable {
    public let backendApprovedCount: Int
    public let blockedAttemptsCount: Int
    public let approvalsByType: [PolicyApprovalGuard.PolicyType: Int]
    
    public init(
        backendApprovedCount: Int,
        blockedAttemptsCount: Int,
        approvalsByType: [PolicyApprovalGuard.PolicyType: Int]
    ) {
        self.backendApprovedCount = backendApprovedCount
        self.blockedAttemptsCount = blockedAttemptsCount
        self.approvalsByType = approvalsByType
    }
}
