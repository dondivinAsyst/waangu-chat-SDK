//
//  OfflineQRGuard.swift
//  SecurityKit
//
//  QR offline forbidden for critical actions
//  Critical actions require online verification
//

import Foundation
import WaanguCoreKit

/// Offline QR guard
/// Critical actions forbidden in offline mode
public actor OfflineQRGuard {
    
    public static let shared = OfflineQRGuard()
    
    private var isOnline: Bool = true
    
    private init() {}
    
    public enum QRActionType: String, Sendable {
        case payment
        case transfer
        case authentication
        case authorization
        case criticalAction
        case nonCritical
    }
    
    public enum OfflineQRError: Error, Sendable {
        case offlineCriticalActionForbidden
        case networkRequired
    }
    
    // MARK: - Public API
    
    /// Set online status
    public func setOnlineStatus(_ online: Bool) {
        self.isOnline = online
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .network,
                metadata: ["operation": "network_status_change", "online": "\(online)"]
            )
        }
    }
    
    /// Validate QR action (critical actions require online)
    public func validateQRAction(qrId: String, actionType: QRActionType) throws {
        // RULE: Critical actions forbidden offline
        if !isOnline && isCriticalAction(actionType) {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: ["violation": "offline_critical_qr_action", "qrId": qrId, "action": actionType.rawValue]
                )
            }
            throw OfflineQRError.offlineCriticalActionForbidden
        }
    }
    
    /// Check if action is critical
    public func isCriticalAction(_ actionType: QRActionType) -> Bool {
        switch actionType {
        case .payment, .transfer, .authentication, .authorization, .criticalAction:
            return true
        case .nonCritical:
            return false
        }
    }
    
    /// Get online status
    public func getOnlineStatus() -> Bool {
        return isOnline
    }
}
