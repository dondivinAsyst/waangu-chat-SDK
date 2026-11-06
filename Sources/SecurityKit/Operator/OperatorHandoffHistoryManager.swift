//
//  OperatorHandoffHistoryManager.swift
//  SecurityKit
//
//  Operator handoff preserves visible history
//  All handoffs tracked with full history
//

import Foundation
import WaanguCoreKit

/// Operator handoff history manager
/// Preserves visible history of all handoffs
public actor OperatorHandoffHistoryManager {
    
    public static let shared = OperatorHandoffHistoryManager()
    
    private var handoffHistory: [HandoffRecord] = []
    
    private init() {}
    
    public struct HandoffRecord: Sendable {
        public let handoffId: String
        public let fromOperator: String?
        public let toOperator: String
        public let userId: String
        public let reason: String
        public let timestamp: Date
        public let evidenceRefs: [String]
        public let visible: Bool
        
        public init(handoffId: String, fromOperator: String?, toOperator: String, userId: String, reason: String, timestamp: Date, evidenceRefs: [String], visible: Bool) {
            self.handoffId = handoffId
            self.fromOperator = fromOperator
            self.toOperator = toOperator
            self.userId = userId
            self.reason = reason
            self.timestamp = timestamp
            self.evidenceRefs = evidenceRefs
            self.visible = visible
        }
    }
    
    // MARK: - Public API
    
    /// Record handoff (always visible)
    public func recordHandoff(
        handoffId: String,
        fromOperator: String?,
        toOperator: String,
        userId: String,
        reason: String,
        evidenceRefs: [String]
    ) {
        // RULE: History is ALWAYS visible
        let record = HandoffRecord(
            handoffId: handoffId,
            fromOperator: fromOperator,
            toOperator: toOperator,
            userId: userId,
            reason: reason,
            timestamp: Date(),
            evidenceRefs: evidenceRefs,
            visible: true // ALWAYS visible
        )
        
        handoffHistory.append(record)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: [
                    "operation": "record_handoff",
                    "handoffId": handoffId,
                    "toOperator": toOperator,
                    "userId": userId
                ]
            )
        }
    }
    
    /// Get handoff history for user (always visible)
    public func getHistory(userId: String) -> [HandoffRecord] {
        return handoffHistory.filter { $0.userId == userId }
    }
    
    /// Get all handoff history
    public func getAllHistory() -> [HandoffRecord] {
        return handoffHistory
    }
    
    /// Get handoff by ID
    public func getHandoff(handoffId: String) -> HandoffRecord? {
        return handoffHistory.first { $0.handoffId == handoffId }
    }
}
