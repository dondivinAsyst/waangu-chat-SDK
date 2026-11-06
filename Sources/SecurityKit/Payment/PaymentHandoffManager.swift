//
//  PaymentHandoffManager.swift
//  SecurityKit
//
//  Manages payment handoff to external providers (WeChat/WhatsApp Pay style)
//  Ensures secure handoff with forensics tracking
//

import Foundation
import WaanguCoreKit

/// Payment handoff manager for external payment providers
/// Tracks handoff with full forensics
public actor PaymentHandoffManager {
    
    public static let shared = PaymentHandoffManager()
    
    private var activeHandoffs: [String: PaymentHandoff] = [:]
    private var completedHandoffs: [String: CompletedHandoff] = [:]
    
    private init() {}
    
    public struct PaymentHandoff: Sendable {
        public let handoffId: String
        public let provider: PaymentProvider
        public let amount: Decimal
        public let currency: String
        public let merchantId: String
        public let startedAt: Date
        public let expiresAt: Date
        public let forensics: HandoffForensics
        
        public init(handoffId: String, provider: PaymentProvider, amount: Decimal, currency: String, merchantId: String, startedAt: Date, expiresAt: Date, forensics: HandoffForensics) {
            self.handoffId = handoffId
            self.provider = provider
            self.amount = amount
            self.currency = currency
            self.merchantId = merchantId
            self.startedAt = startedAt
            self.expiresAt = expiresAt
            self.forensics = forensics
        }
        
        public var isExpired: Bool {
            return Date() > expiresAt
        }
    }
    
    public struct HandoffForensics: Sendable {
        public let deviceId: String
        public let userId: String
        public let ipAddress: String?
        public let userAgent: String?
        public let location: String?
        public let sessionId: String
        
        public init(deviceId: String, userId: String, ipAddress: String?, userAgent: String?, location: String?, sessionId: String) {
            self.deviceId = deviceId
            self.userId = userId
            self.ipAddress = ipAddress
            self.userAgent = userAgent
            self.location = location
            self.sessionId = sessionId
        }
    }
    
    public struct CompletedHandoff: Sendable {
        public let handoffId: String
        public let completedAt: Date
        public let status: HandoffStatus
        public let transactionId: String?
        
        public init(handoffId: String, completedAt: Date, status: HandoffStatus, transactionId: String?) {
            self.handoffId = handoffId
            self.completedAt = completedAt
            self.status = status
            self.transactionId = transactionId
        }
    }
    
    public enum PaymentProvider: String, Sendable {
        case wechatPay
        case whatsappPay
        case applePay
        case googlePay
        case other
    }
    
    public enum HandoffStatus: String, Sendable {
        case success
        case failed
        case cancelled
        case expired
    }
    
    public enum HandoffError: Error, Sendable {
        case invalidProvider
        case expired
        case notFound
        case alreadyCompleted
    }
    
    // MARK: - Public API
    
    /// Initiate payment handoff
    public func initiateHandoff(
        provider: PaymentProvider,
        amount: Decimal,
        currency: String,
        merchantId: String,
        forensics: HandoffForensics,
        expirationMinutes: Int = 10
    ) async -> PaymentHandoff {
        let handoffId = UUID().uuidString
        let expiresAt = Date().addingTimeInterval(TimeInterval(expirationMinutes * 60))
        
        let handoff = PaymentHandoff(
            handoffId: handoffId,
            provider: provider,
            amount: amount,
            currency: currency,
            merchantId: merchantId,
            startedAt: Date(),
            expiresAt: expiresAt,
            forensics: forensics
        )
        
        activeHandoffs[handoffId] = handoff
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .dataModification,
            metadata: [
                "operation": "initiate_payment_handoff",
                "handoffId": handoffId,
                "provider": provider.rawValue,
                "amount": "\(amount)",
                "currency": currency,
                "userId": forensics.userId
            ]
        )
        
        return handoff
    }
    
    /// Complete payment handoff
    public func completeHandoff(
        handoffId: String,
        status: HandoffStatus,
        transactionId: String?
    ) async throws {
        guard let handoff = activeHandoffs[handoffId] else {
            throw HandoffError.notFound
        }
        
        guard !handoff.isExpired else {
            throw HandoffError.expired
        }
        
        let completed = CompletedHandoff(
            handoffId: handoffId,
            completedAt: Date(),
            status: status,
            transactionId: transactionId
        )
        
        completedHandoffs[handoffId] = completed
        activeHandoffs.removeValue(forKey: handoffId)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .dataModification,
            metadata: [
                "operation": "complete_payment_handoff",
                "handoffId": handoffId,
                "status": status.rawValue,
                "transactionId": transactionId ?? "none"
            ]
        )
    }
    
    /// Get active handoff
    public func getHandoff(handoffId: String) -> PaymentHandoff? {
        return activeHandoffs[handoffId]
    }
    
    /// Get completed handoff
    public func getCompletedHandoff(handoffId: String) -> CompletedHandoff? {
        return completedHandoffs[handoffId]
    }
    
    /// Clean up expired handoffs
    public func cleanupExpired() -> [String] {
        let expired = activeHandoffs.values.filter { $0.isExpired }
        let expiredIds = expired.map { $0.handoffId }
        
        for id in expiredIds {
            let completed = CompletedHandoff(
                handoffId: id,
                completedAt: Date(),
                status: .expired,
                transactionId: nil
            )
            completedHandoffs[id] = completed
            activeHandoffs.removeValue(forKey: id)
        }
        
        return expiredIds
    }
    
    /// Get statistics
    public func getStatistics() -> HandoffStatistics {
        return HandoffStatistics(
            activeCount: activeHandoffs.count,
            completedCount: completedHandoffs.count,
            expiredCount: activeHandoffs.values.filter { $0.isExpired }.count
        )
    }
}

// MARK: - Supporting Types

public struct HandoffStatistics: Sendable {
    public let activeCount: Int
    public let completedCount: Int
    public let expiredCount: Int
    
    public init(activeCount: Int, completedCount: Int, expiredCount: Int) {
        self.activeCount = activeCount
        self.completedCount = completedCount
        self.expiredCount = expiredCount
    }
}
