//
//  ComplianceDeletionGuard.swift
//  SecurityKit
//
//  Compliance messages cannot be deleted locally
//  Compliance data is immutable locally
//

import Foundation
import WaanguCoreKit

/// Compliance deletion guard
/// Compliance messages CANNOT be deleted locally
public actor ComplianceDeletionGuard {
    
    public static let shared = ComplianceDeletionGuard()
    
    private var complianceMessages: Set<String> = []
    
    private init() {}
    
    public enum ComplianceType: String, Sendable {
        case gdprNotice
        case termsOfService
        case privacyPolicy
        case consentRecord
        case auditLog
        case regulatoryNotice
    }
    
    public enum DeletionError: Error, Sendable {
        case complianceMessageCannotBeDeleted
        case localDeletionForbidden
    }
    
    // MARK: - Public API
    
    /// Mark message as compliance
    public func markAsCompliance(messageId: String, type: ComplianceType) {
        complianceMessages.insert(messageId)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["operation": "mark_compliance_message", "messageId": messageId, "type": type.rawValue]
            )
        }
    }
    
    /// Validate deletion (compliance messages CANNOT be deleted)
    public func validateDeletion(messageId: String) throws {
        // RULE: Compliance messages cannot be deleted locally
        guard !complianceMessages.contains(messageId) else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: ["violation": "attempt_delete_compliance_message", "messageId": messageId]
                )
            }
            throw DeletionError.complianceMessageCannotBeDeleted
        }
    }
    
    /// Check if message is compliance
    public func isComplianceMessage(messageId: String) -> Bool {
        return complianceMessages.contains(messageId)
    }
    
    /// Get all compliance messages
    public func getAllComplianceMessages() -> Set<String> {
        return complianceMessages
    }
}
