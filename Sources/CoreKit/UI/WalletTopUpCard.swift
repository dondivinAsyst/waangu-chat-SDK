//
//  WalletTopUpCard.swift
//  CoreKit
//
//  Wallet top-up action card
//  Backend-driven wallet top-up UI
//

import Foundation

/// Wallet top-up action card
public struct WalletTopUpCard: Sendable {
    public let cardId: String
    public let title: String
    public let amount: Decimal
    public let currency: String
    public let paymentMethods: [PaymentMethod]
    public let expiresAt: Date?
    
    public init(cardId: String, title: String, amount: Decimal, currency: String, paymentMethods: [PaymentMethod], expiresAt: Date?) {
        self.cardId = cardId
        self.title = title
        self.amount = amount
        self.currency = currency
        self.paymentMethods = paymentMethods
        self.expiresAt = expiresAt
    }
    
    public struct PaymentMethod: Sendable {
        public let methodId: String
        public let name: String
        public let icon: String?
        
        public init(methodId: String, name: String, icon: String?) {
            self.methodId = methodId
            self.name = name
            self.icon = icon
        }
    }
}
