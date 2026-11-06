//
//  ComplianceGateway.swift
//  SecurityKit
//
//  Enforces that all compliance/policy decisions go through Compliance service only

import Foundation
import WaanguCoreKit

public actor ComplianceGateway {

    public static let shared = ComplianceGateway()

    private var complianceServiceURL: URL?
    private let enforceGateway = true

    private init() {}

    // MARK: - Configuration

    public func configure(complianceURL: URL) {
        self.complianceServiceURL = complianceURL
    }

    // MARK: - Policy Decision Validation

    public func validatePolicyDecision(_ decision: PolicyDecision) async throws {
        guard enforceGateway else { return }

        guard complianceServiceURL != nil else {
            throw ComplianceGatewayError.notConfigured
        }

        guard decision.source == .compliance else {
            await logViolation(decision: decision)
            throw ComplianceGatewayError.localPolicyDecisionDetected(
                policy: decision.policyType,
                source: decision.source.rawValue
            )
        }

        guard decision.signature != nil else {
            throw ComplianceGatewayError.unsignedPolicyDecision
        }
    }

    public func requestPolicyDecision(
        policy: PolicyType,
        context: PolicyContext
    ) async throws -> PolicyDecision {
        guard complianceServiceURL != nil else {
            throw ComplianceGatewayError.notConfigured
        }

        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "policy_decision_request",
                "policy": policy.rawValue,
                "user_id": context.userId ?? "unknown"
            ],
            severity: .info
        )

        return PolicyDecision(
            policyType: policy,
            decision: .pending,
            source: .compliance,
            timestamp: Date(),
            signature: "compliance_signature_placeholder",
            context: context
        )
    }

    // MARK: - Forbidden Local Decisions

    private let forbiddenLocalPolicies: Set<PolicyType> = [
        .contentModeration,
        .userBan,
        .accountSuspension,
        .paymentApproval,
        .kycVerification,
        .amlCheck,
        .fraudDetection,
        .regulatoryCompliance
    ]

    public func checkLocalPolicyDecision(_ policy: PolicyType) throws {
        if forbiddenLocalPolicies.contains(policy) {
            throw ComplianceGatewayError.localPolicyDecisionForbidden(policy: policy)
        }
    }

    // MARK: - Compliance Validation

    public func validateCompliance(
        action: ComplianceAction,
        userId: String
    ) async throws -> ComplianceResult {
        guard complianceServiceURL != nil else {
            throw ComplianceGatewayError.notConfigured
        }

        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "compliance_check",
                "compliance_action": action.rawValue,
                "user_id": userId
            ],
            severity: .info
        )

        return ComplianceResult(
            action: action,
            approved: false,
            reason: "Pending Compliance validation",
            timestamp: Date()
        )
    }

    // MARK: - Logging

    private func logViolation(decision: PolicyDecision) async {
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: nil,
            metadata: [
                "violation": "compliance_bypass_attempt",
                "policy": decision.policyType.rawValue,
                "source": decision.source.rawValue
            ]
        )
    }

    // MARK: - Types

    public enum PolicyType: String, Codable {
        case contentModeration
        case userBan
        case accountSuspension
        case paymentApproval
        case kycVerification
        case amlCheck
        case fraudDetection
        case regulatoryCompliance
        case dataRetention
        case privacyControl
    }

    public enum DecisionSource: String, Codable {
        case compliance
        case local
        case cache
        case unknown
    }

    public enum DecisionResult: String, Codable {
        case approved
        case rejected
        case pending
        case requiresReview
    }

    public struct PolicyDecision {
        public let policyType: PolicyType
        public let decision: DecisionResult
        public let source: DecisionSource
        public let timestamp: Date
        public let signature: String?
        public let context: PolicyContext

        public init(policyType: PolicyType, decision: DecisionResult, source: DecisionSource, timestamp: Date, signature: String?, context: PolicyContext) {
            self.policyType = policyType
            self.decision = decision
            self.source = source
            self.timestamp = timestamp
            self.signature = signature
            self.context = context
        }
    }

    public struct PolicyContext {
        public let userId: String?
        public let action: String
        public let resource: String?
        public let metadata: [String: String]

        public init(userId: String?, action: String, resource: String?, metadata: [String: String] = [:]) {
            self.userId = userId
            self.action = action
            self.resource = resource
            self.metadata = metadata
        }
    }

    public enum ComplianceAction: String, Codable {
        case sendMoney
        case receivePayment
        case exportData
        case deleteAccount
        case accessSensitiveData
        case crossBorderTransfer
    }

    public struct ComplianceResult {
        public let action: ComplianceAction
        public let approved: Bool
        public let reason: String
        public let timestamp: Date

        public init(action: ComplianceAction, approved: Bool, reason: String, timestamp: Date) {
            self.action = action
            self.approved = approved
            self.reason = reason
            self.timestamp = timestamp
        }
    }

    public enum ComplianceGatewayError: Error, LocalizedError {
        case notConfigured
        case localPolicyDecisionDetected(policy: PolicyType, source: String)
        case localPolicyDecisionForbidden(policy: PolicyType)
        case unsignedPolicyDecision

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Compliance gateway not configured"
            case .localPolicyDecisionDetected(let policy, let source):
                return "Local policy decision detected: \(policy.rawValue) from \(source). All policy decisions must come from Compliance."
            case .localPolicyDecisionForbidden(let policy):
                return "Local policy decision forbidden: \(policy.rawValue). Must use Compliance service."
            case .unsignedPolicyDecision:
                return "Policy decision missing Compliance signature"
            }
        }
    }
}
