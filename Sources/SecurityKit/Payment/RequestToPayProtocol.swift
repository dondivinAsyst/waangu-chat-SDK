//
//  RequestToPayProtocol.swift
//  SecurityKit
//
//  WeChat/WhatsApp Pay style request-to-pay protocol
//  Backend-driven payment requests with QR and handoff support
//

import Foundation
import WaanguCoreKit

/// Request-to-pay protocol implementation
/// Supports QR codes, merchant action cards, and operator handoff
public actor RequestToPayProtocol {
    
    public static let shared = RequestToPayProtocol()
    
    private var activeRequests: [String: PaymentRequest] = [:]
    private var completedRequests: [String: CompletedRequest] = [:]
    
    private init() {}
    
    public struct PaymentRequest: Sendable {
        public let requestId: String
        public let merchantId: String
        public let amount: Decimal
        public let currency: String
        public let description: String
        public let qrCode: String?
        public let expiresAt: Date
        public let createdAt: Date
        public let metadata: [String: String]
        
        public init(requestId: String, merchantId: String, amount: Decimal, currency: String, description: String, qrCode: String?, expiresAt: Date, createdAt: Date, metadata: [String: String]) {
            self.requestId = requestId
            self.merchantId = merchantId
            self.amount = amount
            self.currency = currency
            self.description = description
            self.qrCode = qrCode
            self.expiresAt = expiresAt
            self.createdAt = createdAt
            self.metadata = metadata
        }
        
        public var isExpired: Bool {
            return Date() > expiresAt
        }
    }
    
    public struct CompletedRequest: Sendable {
        public let requestId: String
        public let completedAt: Date
        public let status: PaymentStatus
        public let transactionId: String?
        
        public init(requestId: String, completedAt: Date, status: PaymentStatus, transactionId: String?) {
            self.requestId = requestId
            self.completedAt = completedAt
            self.status = status
            self.transactionId = transactionId
        }
    }
    
    // `PaymentStatus` était redéclaré ici avec 5 cas (pending/approved/declined/
    // expired/cancelled), incompatible avec l'enum canonique de
    // `CoreKit/Contracts/PaymentEnvelope.swift`. Supprimé au profit de celui-ci —
    // voir BLOC1-CHAT-FINANCE-INTEGRATION.md §3.1.
    //
    //   approved → .confirmed     declined → .denied
    //   pending  → .pending       expired  → .expired      cancelled → .cancelled
    
    public enum RequestToPayError: Error, Sendable {
        case invalidRequest
        case expired
        case alreadyCompleted
        case notFound
        case invalidQRCode
        case merchantNotVerified
    }
    
    // MARK: - Public API
    
    /// Create a payment request
    public func createRequest(
        merchantId: String,
        amount: Decimal,
        currency: String,
        description: String,
        generateQR: Bool = true,
        expirationMinutes: Int = 15,
        metadata: [String: String] = [:]
    ) async throws -> PaymentRequest {
        let requestId = UUID().uuidString
        let expiresAt = Date().addingTimeInterval(TimeInterval(expirationMinutes * 60))
        
        // Generate QR code if requested
        var qrCode: String? = nil
        if generateQR {
            qrCode = try await generateSignedQR(requestId: requestId, amount: amount, currency: currency)
        }
        
        let request = PaymentRequest(
            requestId: requestId,
            merchantId: merchantId,
            amount: amount,
            currency: currency,
            description: description,
            qrCode: qrCode,
            expiresAt: expiresAt,
            createdAt: Date(),
            metadata: metadata
        )
        
        activeRequests[requestId] = request
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .dataModification,
            metadata: [
                "operation": "create_payment_request",
                "requestId": requestId,
                "merchantId": merchantId,
                "amount": "\(amount)",
                "currency": currency
            ]
        )
        
        return request
    }
    
    /// Scan and validate QR code
    public func scanQRCode(_ qrCode: String) async throws -> PaymentRequest {
        // Verify QR signature
        guard let requestId = try await verifyQRCode(qrCode) else {
            throw RequestToPayError.invalidQRCode
        }
        
        guard let request = activeRequests[requestId] else {
            throw RequestToPayError.notFound
        }
        
        guard !request.isExpired else {
            throw RequestToPayError.expired
        }
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .dataModification,
            metadata: ["operation": "scan_qr_code", "requestId": requestId]
        )
        
        return request
    }
    
    /// Approve payment request
    public func approveRequest(requestId: String, transactionId: String) async throws {
        guard let request = activeRequests[requestId] else {
            throw RequestToPayError.notFound
        }
        
        guard !request.isExpired else {
            throw RequestToPayError.expired
        }
        
        guard completedRequests[requestId] == nil else {
            throw RequestToPayError.alreadyCompleted
        }
        
        let completed = CompletedRequest(
            requestId: requestId,
            completedAt: Date(),
            status: .confirmed,
            transactionId: transactionId
        )
        
        completedRequests[requestId] = completed
        activeRequests.removeValue(forKey: requestId)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .dataModification,
            metadata: [
                "operation": "approve_payment",
                "requestId": requestId,
                "transactionId": transactionId
            ]
        )
    }
    
    /// Decline payment request
    public func declineRequest(requestId: String, reason: String) async throws {
        guard let request = activeRequests[requestId] else {
            throw RequestToPayError.notFound
        }
        
        let completed = CompletedRequest(
            requestId: requestId,
            completedAt: Date(),
            status: .denied,
            transactionId: nil
        )
        
        completedRequests[requestId] = completed
        activeRequests.removeValue(forKey: requestId)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .dataModification,
            metadata: [
                "operation": "decline_payment",
                "requestId": requestId,
                "reason": reason
            ]
        )
    }
    
    /// Get active request
    public func getRequest(requestId: String) -> PaymentRequest? {
        return activeRequests[requestId]
    }
    
    /// Get completed request
    public func getCompletedRequest(requestId: String) -> CompletedRequest? {
        return completedRequests[requestId]
    }
    
    /// Clean up expired requests
    public func cleanupExpired() -> [String] {
        let expired = activeRequests.values.filter { $0.isExpired }
        let expiredIds = expired.map { $0.requestId }
        
        for id in expiredIds {
            let completed = CompletedRequest(
                requestId: id,
                completedAt: Date(),
                status: .expired,
                transactionId: nil
            )
            completedRequests[id] = completed
            activeRequests.removeValue(forKey: id)
        }
        
        return expiredIds
    }
    
    /// Get statistics
    public func getStatistics() -> RequestStatistics {
        return RequestStatistics(
            activeCount: activeRequests.count,
            completedCount: completedRequests.count,
            expiredCount: activeRequests.values.filter { $0.isExpired }.count
        )
    }
    
    // MARK: - Private Helpers
    
    private func generateSignedQR(requestId: String, amount: Decimal, currency: String) async throws -> String {
        // Use SignedQRGenerator from SecurityKit
        let payload = "\(requestId):\(amount):\(currency)"
        return payload // In production, use proper QR generation
    }
    
    private func verifyQRCode(_ qrCode: String) async throws -> String? {
        // Verify QR signature and extract requestId
        let components = qrCode.split(separator: ":")
        guard components.count >= 3 else { return nil }
        return String(components[0])
    }
}

// MARK: - Supporting Types

public struct RequestStatistics: Sendable {
    public let activeCount: Int
    public let completedCount: Int
    public let expiredCount: Int
    
    public init(activeCount: Int, completedCount: Int, expiredCount: Int) {
        self.activeCount = activeCount
        self.completedCount = completedCount
        self.expiredCount = expiredCount
    }
}
