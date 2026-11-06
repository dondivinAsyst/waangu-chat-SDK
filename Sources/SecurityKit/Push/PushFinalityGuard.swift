//
//  PushFinalityGuard.swift
//  SecurityKit
//
//  Push notifications NEVER finalize operations
//  Pushes only trigger actions, never finalize
//

import Foundation
import WaanguCoreKit

/// Push finality guard - pushes NEVER finalize
/// Pushes can only trigger, never finalize operations
public actor PushFinalityGuard {
    
    public static let shared = PushFinalityGuard()
    
    private var pushTriggers: [String: PushTrigger] = [:]
    
    private init() {}
    
    public struct PushTrigger: Sendable {
        public let pushId: String
        public let action: TriggerAction
        public let triggeredAt: Date
        
        public init(pushId: String, action: TriggerAction, triggeredAt: Date) {
            self.pushId = pushId
            self.action = action
            self.triggeredAt = triggeredAt
        }
    }
    
    public enum TriggerAction: String, Sendable {
        case resync
        case notification
        case refresh
        case alert
    }
    
    public enum PushFinalityError: Error, Sendable {
        case pushCannotFinalize
        case invalidAction
    }
    
    // MARK: - Public API
    
    /// Handle push (can only trigger, never finalize)
    public func handlePush(pushId: String, action: TriggerAction) {
        let trigger = PushTrigger(
            pushId: pushId,
            action: action,
            triggeredAt: Date()
        )
        
        pushTriggers[pushId] = trigger
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "push_trigger", "pushId": pushId, "action": action.rawValue]
            )
        }
    }
    
    /// Attempt to finalize with push (BLOCKED - pushes never finalize)
    public func attemptFinalization(pushId: String) throws {
        Task {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: nil,
                metadata: ["violation": "push_finalization_attempt", "pushId": pushId]
            )
        }
        throw PushFinalityError.pushCannotFinalize
    }
    
    /// Check if push exists
    public func hasPush(pushId: String) -> Bool {
        return pushTriggers[pushId] != nil
    }
}
