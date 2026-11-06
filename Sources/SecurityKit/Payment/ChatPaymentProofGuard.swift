//
//  ChatPaymentProofGuard.swift
//  SecurityKit
//
//  Chat payments require backend proof AND external rail
//  No local payment finalization allowed
//

import Foundation
import WaanguCoreKit

/// Chat payment proof guard
/// Requires backend proof + external payment rail
///
/// - Warning: **Doublon — non normatif.** Trois types portaient la même décision :
///   celui-ci, `RailProofValidator` et `PaymentConfirmationGuard`. Le chemin
///   normatif du Bloc 1 est `PaymentConfirmationGuardProtocol.decide(on:)`, qui
///   vérifie signature, fraîcheur de révision et preuve de rail en un seul verdict
///   motivé — et qui est le seul des trois injecté dans `ChatDependencies`.
///
///   Conservé sans appelant pour ne rien casser ; à supprimer avec la tâche 2.7
///   une fois confirmé qu'aucune intégration ne s'y adosse.
public actor ChatPaymentProofGuard {
    
    public static let shared = ChatPaymentProofGuard()
    
    private var pendingPayments: [String: PendingChatPayment] = [:]
    private var verifiedPayments: [String: VerifiedPayment] = [:]
    
    private init() {}
    
    public struct PendingChatPayment: Sendable {
        public let paymentId: String
        public let amount: Decimal
        public let currency: String
        public let chatId: String
        public let senderId: String
        public let recipientId: String
        public let createdAt: Date
        
        public init(paymentId: String, amount: Decimal, currency: String, chatId: String, senderId: String, recipientId: String, createdAt: Date) {
            self.paymentId = paymentId
            self.amount = amount
            self.currency = currency
            self.chatId = chatId
            self.senderId = senderId
            self.recipientId = recipientId
            self.createdAt = createdAt
        }
    }
    
    public struct VerifiedPayment: Sendable {
        public let paymentId: String
        public let backendProof: String
        public let externalRailId: String
        public let externalRail: ExternalRail
        public let verifiedAt: Date
        
        public init(paymentId: String, backendProof: String, externalRailId: String, externalRail: ExternalRail, verifiedAt: Date) {
            self.paymentId = paymentId
            self.backendProof = backendProof
            self.externalRailId = externalRailId
            self.externalRail = externalRail
            self.verifiedAt = verifiedAt
        }
    }
    
    public enum ExternalRail: String, Sendable {
        case stripe
        case paypal
        case bankTransfer
        case wechatPay
        case whatsappPay
        case applePay
    }
    
    public enum PaymentProofError: Error, Sendable {
        case noBackendProof
        case noExternalRail
        case invalidProof
        case notPending
    }
    
    // MARK: - Public API
    
    /// Initiate chat payment
    public func initiatePayment(
        paymentId: String,
        amount: Decimal,
        currency: String,
        chatId: String,
        senderId: String,
        recipientId: String
    ) {
        let payment = PendingChatPayment(
            paymentId: paymentId,
            amount: amount,
            currency: currency,
            chatId: chatId,
            senderId: senderId,
            recipientId: recipientId,
            createdAt: Date()
        )
        
        pendingPayments[paymentId] = payment
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .dataModification,
                metadata: ["operation": "initiate_chat_payment", "paymentId": paymentId, "amount": "\(amount)"]
            )
        }
    }
    
    /// Verify payment with backend proof AND external rail
    public func verifyPayment(
        paymentId: String,
        backendProof: String,
        externalRailId: String,
        externalRail: ExternalRail
    ) throws {
        guard pendingPayments[paymentId] != nil else {
            throw PaymentProofError.notPending
        }
        
        // RULE: Must have backend proof
        guard !backendProof.isEmpty else {
            throw PaymentProofError.noBackendProof
        }
        
        // RULE: Must have external rail
        guard !externalRailId.isEmpty else {
            throw PaymentProofError.noExternalRail
        }
        
        let verified = VerifiedPayment(
            paymentId: paymentId,
            backendProof: backendProof,
            externalRailId: externalRailId,
            externalRail: externalRail,
            verifiedAt: Date()
        )
        
        verifiedPayments[paymentId] = verified
        pendingPayments.removeValue(forKey: paymentId)
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .dataModification,
                metadata: [
                    "operation": "verify_chat_payment",
                    "paymentId": paymentId,
                    "rail": externalRail.rawValue
                ]
            )
        }
    }
    
    /// Check if payment is verified
    public func isVerified(paymentId: String) -> Bool {
        return verifiedPayments[paymentId] != nil
    }
}
