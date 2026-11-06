//
//  RailProofValidator.swift
//  SecurityKit
//
//  pendingExternal → confirmed requires RailProof
//  External payment confirmation requires proof
//

import Foundation
import WaanguCoreKit

/// Rail proof validator
/// External payments require rail proof for confirmation
///
/// - Note: **Non normatif pour la décision d'affichage.** L'exigence
///   « `pendingExternal → confirmed` requiert une `RailProof` » est appliquée par
///   `PaymentConfirmationGuard.decide(on:)`, étape 4. Ce type reste utile pour
///   suivre le cycle de vie d'une preuve de rail, pas pour décider si une carte
///   s'affiche comme confirmée.
public actor RailProofValidator {
    
    public static let shared = RailProofValidator()
    
    private var pendingPayments: [String: PendingExternalPayment] = [:]
    private var confirmedPayments: [String: ConfirmedPayment] = [:]
    
    private init() {}
    
    public struct PendingExternalPayment: Sendable {
        public let paymentId: String
        public let externalRail: String
        public let amount: Decimal
        public let createdAt: Date
        
        public init(paymentId: String, externalRail: String, amount: Decimal, createdAt: Date) {
            self.paymentId = paymentId
            self.externalRail = externalRail
            self.amount = amount
            self.createdAt = createdAt
        }
    }
    
    public struct ConfirmedPayment: Sendable {
        public let paymentId: String
        public let railProof: String
        public let confirmedAt: Date
        
        public init(paymentId: String, railProof: String, confirmedAt: Date) {
            self.paymentId = paymentId
            self.railProof = railProof
            self.confirmedAt = confirmedAt
        }
    }
    
    public enum RailProofError: Error, Sendable {
        case noRailProof
        case invalidProof
        case notPending
    }
    
    // MARK: - Public API
    
    /// Register pending external payment
    public func registerPending(paymentId: String, externalRail: String, amount: Decimal) {
        let pending = PendingExternalPayment(
            paymentId: paymentId,
            externalRail: externalRail,
            amount: amount,
            createdAt: Date()
        )
        
        pendingPayments[paymentId] = pending
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .dataModification,
                metadata: ["operation": "register_pending_external", "paymentId": paymentId, "rail": externalRail]
            )
        }
    }
    
    /// Confirm payment (REQUIRES RailProof)
    public func confirmPayment(paymentId: String, railProof: String) throws {
        guard let pending = pendingPayments[paymentId] else {
            throw RailProofError.notPending
        }
        
        // RULE: Must have rail proof
        guard !railProof.isEmpty else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: nil,
                    metadata: ["violation": "confirm_without_rail_proof", "paymentId": paymentId]
                )
            }
            throw RailProofError.noRailProof
        }
        
        let confirmed = ConfirmedPayment(
            paymentId: paymentId,
            railProof: railProof,
            confirmedAt: Date()
        )
        
        confirmedPayments[paymentId] = confirmed
        pendingPayments.removeValue(forKey: paymentId)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .dataModification,
                metadata: ["operation": "confirm_external_payment", "paymentId": paymentId]
            )
        }
    }
    
    /// Check if payment is confirmed
    public func isConfirmed(paymentId: String) -> Bool {
        return confirmedPayments[paymentId] != nil
    }
}
