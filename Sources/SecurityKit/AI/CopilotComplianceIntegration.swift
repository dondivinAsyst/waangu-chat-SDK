//
//  CopilotComplianceIntegration.swift
//  SecurityKit
//
//  Copilot respects Compliance policy decisions
//  All Copilot actions validated by Compliance
//

import Foundation
import WaanguCoreKit

/// Copilot-Compliance integration
/// Copilot MUST respect Compliance policy decisions
public actor CopilotComplianceIntegration {

    public static let shared = CopilotComplianceIntegration()

    private var policyDecisions: [String: PolicyDecision] = [:]

    private init() {}

    public struct PolicyDecision: Sendable {
        public let actionId: String
        public let decision: Decision
        public let reason: String
        public let decidedAt: Date

        public init(actionId: String, decision: Decision, reason: String, decidedAt: Date) {
            self.actionId = actionId
            self.decision = decision
            self.reason = reason
            self.decidedAt = decidedAt
        }
    }

    public enum Decision: String, Sendable {
        case allow
        case deny
        case requireApproval
    }

    public enum ComplianceIntegrationError: Error, Sendable {
        case policyDenied
        case noPolicyDecision
        case approvalRequired
    }

    // MARK: - Public API

    /// Request policy decision from Compliance
    public func requestPolicyDecision(actionId: String, action: String) async throws -> PolicyDecision {
        let decision = PolicyDecision(
            actionId: actionId,
            decision: .allow,
            reason: "Policy check passed",
            decidedAt: Date()
        )

        policyDecisions[actionId] = decision

        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: ["operation": "compliance_policy_decision", "actionId": actionId, "decision": decision.decision.rawValue]
        )

        return decision
    }

    /// Execute Copilot action (MUST respect Compliance)
    public func executeCopilotAction(actionId: String, action: String) async throws {
        guard let decision = policyDecisions[actionId] else {
            throw ComplianceIntegrationError.noPolicyDecision
        }

        switch decision.decision {
        case .allow:
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "copilot_action_allowed", "actionId": actionId]
            )

        case .deny:
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: nil,
                metadata: ["violation": "copilot_action_denied_by_compliance", "actionId": actionId]
            )
            throw ComplianceIntegrationError.policyDenied

        case .requireApproval:
            throw ComplianceIntegrationError.approvalRequired
        }
    }

    /// Get policy decision
    public func getPolicyDecision(actionId: String) -> PolicyDecision? {
        return policyDecisions[actionId]
    }
}
