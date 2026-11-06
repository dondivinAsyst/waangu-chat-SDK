//
//  OperatorTakeoverGuard.swift
//  SecurityKit
//
//  Operator takeover requires evidenceRefs
//  No takeover without evidence trail
//

import Foundation
import WaanguCoreKit

/// Operator takeover guard
/// All takeovers require evidenceRefs
public actor OperatorTakeoverGuard {
    
    public static let shared = OperatorTakeoverGuard()
    
    private var activeTakeovers: [String: OperatorTakeover] = [:]
    
    private init() {}
    
    public struct OperatorTakeover: Sendable {
        public let takeoverId: String
        public let operatorId: String
        public let userId: String
        public let reason: String
        public let evidenceRefs: [String]
        public let startedAt: Date
        
        public init(takeoverId: String, operatorId: String, userId: String, reason: String, evidenceRefs: [String], startedAt: Date) {
            self.takeoverId = takeoverId
            self.operatorId = operatorId
            self.userId = userId
            self.reason = reason
            self.evidenceRefs = evidenceRefs
            self.startedAt = startedAt
        }
    }
    
    public enum TakeoverError: Error, Sendable {
        case noEvidenceRefs
        case insufficientEvidence
        case invalidTakeover
    }
    
    // MARK: - Public API
    
    /// Initiate takeover (requires evidenceRefs)
    public func initiateTakeover(
        takeoverId: String,
        operatorId: String,
        userId: String,
        reason: String,
        evidenceRefs: [String]
    ) throws {
        // RULE: Must have evidenceRefs
        guard !evidenceRefs.isEmpty else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: operatorId,
                    metadata: ["violation": "takeover_no_evidence", "userId": userId]
                )
            }
            throw TakeoverError.noEvidenceRefs
        }
        
        let takeover = OperatorTakeover(
            takeoverId: takeoverId,
            operatorId: operatorId,
            userId: userId,
            reason: reason,
            evidenceRefs: evidenceRefs,
            startedAt: Date()
        )
        
        activeTakeovers[takeoverId] = takeover
        
        Task {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: operatorId,
                metadata: [
                    "operation": "operator_takeover",
                    "takeoverId": takeoverId,
                    "userId": userId,
                    "evidenceCount": "\(evidenceRefs.count)"
                ]
            )
        }
    }
    
    /// End takeover
    public func endTakeover(takeoverId: String) {
        activeTakeovers.removeValue(forKey: takeoverId)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["operation": "end_takeover", "takeoverId": takeoverId]
            )
        }
    }
}
