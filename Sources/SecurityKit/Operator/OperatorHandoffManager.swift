//
//  OperatorHandoffManager.swift
//  CoreKit
//
//  Manages operator handoff with forensics
//  RULE: Handoff opérateur avec forensic

import Foundation
import WaanguCoreKit

public actor OperatorHandoffManager {
    
    public static let shared = OperatorHandoffManager()
    
    private var handoffs: [String: OperatorHandoff] = [:]
    
    private init() {}
    
    // MARK: - Operator Handoff
    
    /// Creates operator handoff with forensics
    /// RULE: Handoff opérateur avec forensic
    public func createHandoff(
        sessionId: String,
        userId: String,
        reason: HandoffReason,
        context: [String: String]
    ) async -> OperatorHandoff {
        
        // Collect forensics
        let forensics = await collectForensics(sessionId: sessionId, userId: userId)
        
        let handoff = OperatorHandoff(
            id: UUID().uuidString,
            sessionId: sessionId,
            userId: userId,
            reason: reason,
            context: context,
            forensics: forensics,
            createdAt: Date(),
            status: .pending
        )
        
        handoffs[handoff.id] = handoff
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "operator_handoff_created",
                "handoff_id": handoff.id,
                "user_id": userId,
                "reason": reason.rawValue,
                "forensics_count": String(forensics.events.count)
            ],
            severity: .info
        )
        
        return handoff
    }
    
    /// Collects forensic data for handoff
    private func collectForensics(sessionId: String, userId: String) async -> ForensicData {
        
        // Collect recent audit events
        let recentEvents = await AuditBreadcrumb.shared.getRecent(limit: 100)
        
        // Collect system state
        let systemState = [
            "timestamp": Date().ISO8601Format(),
            "session_id": sessionId,
            "user_id": userId,
            "platform": "iOS"
        ]
        
        // Collect security events
        let securityEvents = recentEvents.filter { $0.category == .security }
        
        return ForensicData(
            sessionId: sessionId,
            userId: userId,
            events: recentEvents.map { event in
                ForensicEvent(
                    timestamp: Date(),
                    action: event.action.rawValue,
                    category: event.category.rawValue,
                    metadata: event.metadata
                )
            },
            systemState: systemState,
            securityEvents: securityEvents.map { $0.metadata },
            collectedAt: Date()
        )
    }
    
    /// Completes operator handoff
    public func completeHandoff(
        handoffId: String,
        operatorId: String,
        resolution: String
    ) async throws {
        
        guard var handoff = handoffs[handoffId] else {
            throw HandoffError.handoffNotFound(handoffId: handoffId)
        }
        
        handoff.status = .completed
        handoff.operatorId = operatorId
        handoff.resolution = resolution
        handoff.completedAt = Date()
        
        handoffs[handoffId] = handoff
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "operator_handoff_completed",
                "handoff_id": handoffId,
                "operator_id": operatorId
            ],
            severity: .info
        )
    }
    
    /// Gets handoff by ID
    public func getHandoff(_ handoffId: String) -> OperatorHandoff? {
        handoffs[handoffId]
    }
    
    /// Gets all handoffs for user
    public func getHandoffsForUser(_ userId: String) -> [OperatorHandoff] {
        handoffs.values.filter { $0.userId == userId }
    }
    
    // MARK: - Types
    
    public struct OperatorHandoff {
        public let id: String
        public let sessionId: String
        public let userId: String
        public let reason: HandoffReason
        public let context: [String: String]
        public let forensics: ForensicData
        public let createdAt: Date
        public var status: HandoffStatus
        public var operatorId: String?
        public var resolution: String?
        public var completedAt: Date?
    }
    
    public struct ForensicData {
        public let sessionId: String
        public let userId: String
        public let events: [ForensicEvent]
        public let systemState: [String: String]
        public let securityEvents: [[String: String]]
        public let collectedAt: Date
    }
    
    public struct ForensicEvent {
        public let timestamp: Date
        public let action: String
        public let category: String
        public let metadata: [String: String]
    }
    
    public enum HandoffReason: String {
        case suspiciousBehavior
        case fraudDetection
        case complianceIssue
        case technicalSupport
        case accountRecovery
        case disputeResolution
    }
    
    public enum HandoffStatus: String {
        case pending
        case inProgress
        case completed
        case cancelled
    }
    
    public enum HandoffError: Error, LocalizedError {
        case handoffNotFound(handoffId: String)
        
        public var errorDescription: String? {
            switch self {
            case .handoffNotFound(let handoffId):
                return "Operator handoff not found: \(handoffId)"
            }
        }
    }
}
