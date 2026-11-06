//
//  PushResyncTrigger.swift
//  SecurityKit
//
//  Push final triggers resync ONLY
//  No other actions allowed on final push
//

import Foundation
import WaanguCoreKit

/// Push resync trigger
/// Final pushes trigger resync only, no other actions
public actor PushResyncTrigger {
    
    public static let shared = PushResyncTrigger()
    
    private var finalPushes: Set<String> = []
    private var resyncTriggered: [String: Date] = [:]
    
    private init() {}
    
    public enum PushType: String, Sendable {
        case final
        case intermediate
        case notification
    }
    
    public enum PushError: Error, Sendable {
        case notFinalPush
        case invalidAction
        case resyncAlreadyTriggered
    }
    
    // MARK: - Public API
    
    /// Handle push (final pushes trigger resync ONLY)
    public func handlePush(pushId: String, type: PushType) throws {
        if type == .final {
            // RULE: Final push can ONLY trigger resync
            try triggerResyncOnly(pushId: pushId)
        } else {
            // Non-final pushes can have other actions
            Task {
                await AuditBreadcrumb.shared.record(
                    action: .dataViewed,
                    category: .system,
                    metadata: ["operation": "handle_push", "pushId": pushId, "type": type.rawValue]
                )
            }
        }
    }
    
    /// Trigger resync from final push
    private func triggerResyncOnly(pushId: String) throws {
        guard !resyncTriggered.keys.contains(pushId) else {
            throw PushError.resyncAlreadyTriggered
        }
        
        finalPushes.insert(pushId)
        resyncTriggered[pushId] = Date()
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "final_push_resync", "pushId": pushId]
            )
        }
    }
    
    /// Attempt non-resync action on final push (BLOCKED)
    public func attemptNonResyncAction(pushId: String, action: String) throws {
        guard finalPushes.contains(pushId) else {
            return // Not a final push, allow
        }
        
        // RULE: Final pushes can ONLY trigger resync
        Task {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: nil,
                metadata: ["violation": "final_push_non_resync_action", "pushId": pushId, "action": action]
            )
        }
        throw PushError.invalidAction
    }
    
    /// Check if push is final
    public func isFinalPush(pushId: String) -> Bool {
        return finalPushes.contains(pushId)
    }
}
