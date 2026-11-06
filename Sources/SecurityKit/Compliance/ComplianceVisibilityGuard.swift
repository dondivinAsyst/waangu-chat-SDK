//
//  ComplianceVisibilityGuard.swift
//  SecurityKit
//
//  Ensures compliance is always visible
//  No hidden compliance states
//

import Foundation
import WaanguCoreKit

/// Compliance visibility guard
/// All compliance states must be visible to users
public actor ComplianceVisibilityGuard {
    
    public static let shared = ComplianceVisibilityGuard()
    
    private var complianceStates: [String: ComplianceState] = [:]
    
    private init() {}
    
    public struct ComplianceState: Sendable {
        public let userId: String
        public let status: ComplianceStatus
        public let requirements: [String]
        public let lastChecked: Date
        public let visible: Bool
        
        public init(userId: String, status: ComplianceStatus, requirements: [String], lastChecked: Date, visible: Bool) {
            self.userId = userId
            self.status = status
            self.requirements = requirements
            self.lastChecked = lastChecked
            self.visible = visible
        }
    }
    
    public enum ComplianceStatus: String, Sendable {
        case compliant
        case pendingReview
        case requiresAction
        case nonCompliant
    }
    
    public enum ComplianceError: Error, Sendable {
        case hiddenCompliance
        case notVisible
    }
    
    // MARK: - Public API
    
    /// Set compliance state (MUST be visible)
    public func setComplianceState(
        userId: String,
        status: ComplianceStatus,
        requirements: [String]
    ) throws {
        // RULE: Compliance MUST be visible
        let state = ComplianceState(
            userId: userId,
            status: status,
            requirements: requirements,
            lastChecked: Date(),
            visible: true // ALWAYS visible
        )
        
        complianceStates[userId] = state
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["operation": "set_compliance_state", "userId": userId, "status": status.rawValue]
            )
        }
    }
    
    /// Get compliance state (always visible)
    public func getComplianceState(userId: String) -> ComplianceState? {
        return complianceStates[userId]
    }
    
    /// Attempt to hide compliance (BLOCKED)
    public func attemptHideCompliance(userId: String) throws {
        Task {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: userId,
                metadata: ["violation": "attempt_hide_compliance"]
            )
        }
        throw ComplianceError.hiddenCompliance
    }
}
