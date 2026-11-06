//
//  MerchantRefundCard.swift
//  CoreKit
//
//  Merchant refund action card
//  Backend-driven refund UI
//

import Foundation

/// Merchant refund action card
public struct MerchantRefundCard: Sendable {
    public let cardId: String
    public let title: String
    public let merchantName: String
    public let originalAmount: Decimal
    public let refundAmount: Decimal
    public let currency: String
    public let reason: String
    public let transactionId: String
    public let expiresAt: Date?
    
    public init(cardId: String, title: String, merchantName: String, originalAmount: Decimal, refundAmount: Decimal, currency: String, reason: String, transactionId: String, expiresAt: Date?) {
        self.cardId = cardId
        self.title = title
        self.merchantName = merchantName
        self.originalAmount = originalAmount
        self.refundAmount = refundAmount
        self.currency = currency
        self.reason = reason
        self.transactionId = transactionId
        self.expiresAt = expiresAt
    }
}
