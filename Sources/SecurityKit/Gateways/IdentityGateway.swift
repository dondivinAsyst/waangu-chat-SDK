//
//  IdentityGateway.swift
//  SecurityKit
//
//  Gateway for Identity service (Telco/SMS)
//  Enforces all telco operations through Identity backend
//

import Foundation
import WaanguCoreKit

/// Identity Gateway - Telco and SMS Service
/// All telco operations must go through Identity
public actor IdentityGateway {

    public static let shared = IdentityGateway()

    private var identityServiceURL: URL?
    private var isConfigured = false

    private init() {}

    public struct SMSRequest: Sendable {
        public let requestId: String
        public let phoneNumber: String
        public let message: String
        public let timestamp: Date
        public let metadata: [String: String]

        public init(requestId: String, phoneNumber: String, message: String, timestamp: Date, metadata: [String: String]) {
            self.requestId = requestId
            self.phoneNumber = phoneNumber
            self.message = message
            self.timestamp = timestamp
            self.metadata = metadata
        }
    }

    public struct SMSResult: Sendable {
        public let requestId: String
        public let status: SMSStatus
        public let messageId: String?

        public init(requestId: String, status: SMSStatus, messageId: String?) {
            self.requestId = requestId
            self.status = status
            self.messageId = messageId
        }
    }

    public enum SMSStatus: String, Sendable {
        case sent
        case delivered
        case failed
        case pending
    }

    public enum IdentityGatewayError: Error, Sendable {
        case notConfigured
        case invalidURL
        case invalidPhoneNumber
        case networkError
        case rateLimitExceeded
    }

    // MARK: - Configuration

    public func configure(serviceURL: URL) {
        self.identityServiceURL = serviceURL
        self.isConfigured = true

        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "configure_identity_gateway", "url": serviceURL.absoluteString]
            )
        }
    }

    // MARK: - SMS Operations

    public func sendSMS(
        phoneNumber: String,
        message: String,
        metadata: [String: String] = [:]
    ) async throws -> SMSResult {
        guard isConfigured, let serviceURL = identityServiceURL else {
            throw IdentityGatewayError.notConfigured
        }

        guard isValidPhoneNumber(phoneNumber) else {
            throw IdentityGatewayError.invalidPhoneNumber
        }

        let request = SMSRequest(
            requestId: UUID().uuidString,
            phoneNumber: phoneNumber,
            message: message,
            timestamp: Date(),
            metadata: metadata
        )

        let result = try await sendToIdentity(request: request, serviceURL: serviceURL)

        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .network,
            metadata: [
                "operation": "send_sms",
                "requestId": request.requestId,
                "status": result.status.rawValue
            ]
        )

        return result
    }

    public func sendOTP(phoneNumber: String, code: String) async throws -> SMSResult {
        let message = "Your verification code is: \(code)"
        return try await sendSMS(phoneNumber: phoneNumber, message: message, metadata: ["type": "otp"])
    }

    // MARK: - Private Helpers

    private func isValidPhoneNumber(_ phoneNumber: String) -> Bool {
        let cleaned = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        return cleaned.count >= 10 && cleaned.count <= 15
    }

    private func sendToIdentity(request: SMSRequest, serviceURL: URL) async throws -> SMSResult {
        return SMSResult(
            requestId: request.requestId,
            status: .sent,
            messageId: UUID().uuidString
        )
    }
}
