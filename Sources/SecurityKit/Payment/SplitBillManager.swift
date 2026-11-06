//
//  SplitBillManager.swift
//  SecurityKit
//
//  Split bill with idempotency
//  Ensures split operations are idempotent
//

import Foundation
import WaanguCoreKit

/// Split bill manager - idempotent operations
/// All split operations are idempotent
public actor SplitBillManager {
    
    public static let shared = SplitBillManager()
    
    private var activeSplits: [String: SplitBill] = [:]
    private var processedOperations: Set<String> = []
    
    private init() {}
    
    public struct SplitBill: Sendable {
        public let splitId: String
        public let totalAmount: Decimal
        public let currency: String
        public let participants: [Participant]
        public let createdBy: String
        public let createdAt: Date
        
        public init(splitId: String, totalAmount: Decimal, currency: String, participants: [Participant], createdBy: String, createdAt: Date) {
            self.splitId = splitId
            self.totalAmount = totalAmount
            self.currency = currency
            self.participants = participants
            self.createdBy = createdBy
            self.createdAt = createdAt
        }
    }
    
    public struct Participant: Sendable {
        public let userId: String
        public let amount: Decimal
        public let paid: Bool
        
        public init(userId: String, amount: Decimal, paid: Bool) {
            self.userId = userId
            self.amount = amount
            self.paid = paid
        }
    }
    
    public enum SplitBillError: Error, Sendable {
        case duplicateOperation
        case notFound
    }
    
    // MARK: - Public API
    
    /// Create split bill (idempotent)
    public func createSplit(
        splitId: String,
        totalAmount: Decimal,
        currency: String,
        participants: [Participant],
        createdBy: String,
        idempotencyKey: String
    ) throws {
        // RULE: Idempotent - check if already processed
        guard !processedOperations.contains(idempotencyKey) else {
            throw SplitBillError.duplicateOperation
        }
        
        let split = SplitBill(
            splitId: splitId,
            totalAmount: totalAmount,
            currency: currency,
            participants: participants,
            createdBy: createdBy,
            createdAt: Date()
        )
        
        activeSplits[splitId] = split
        processedOperations.insert(idempotencyKey)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .dataModification,
                metadata: ["operation": "create_split_bill", "splitId": splitId, "amount": "\(totalAmount)"]
            )
        }
    }
    
    /// Mark participant as paid (idempotent)
    public func markPaid(
        splitId: String,
        userId: String,
        idempotencyKey: String
    ) throws {
        guard var split = activeSplits[splitId] else {
            throw SplitBillError.notFound
        }
        
        // RULE: Idempotent
        guard !processedOperations.contains(idempotencyKey) else {
            return // Already processed
        }
        
        let updatedParticipants = split.participants.map { participant in
            if participant.userId == userId {
                return Participant(userId: participant.userId, amount: participant.amount, paid: true)
            }
            return participant
        }
        
        split = SplitBill(
            splitId: split.splitId,
            totalAmount: split.totalAmount,
            currency: split.currency,
            participants: updatedParticipants,
            createdBy: split.createdBy,
            createdAt: split.createdAt
        )
        
        activeSplits[splitId] = split
        processedOperations.insert(idempotencyKey)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .dataModification,
                metadata: ["operation": "mark_paid", "splitId": splitId, "userId": userId]
            )
        }
    }
}
