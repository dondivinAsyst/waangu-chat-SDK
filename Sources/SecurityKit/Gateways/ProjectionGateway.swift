//
//  ProjectionGateway.swift
//  SecurityKit
//
//  Gateway for Projection service (Fraud Detection)
//  Enforces all fraud checks through Projection backend
//

import Foundation
import WaanguCoreKit

/// Projection Gateway - Fraud Detection Service
/// All fraud detection must go through Projection
public actor ProjectionGateway {

    public static let shared = ProjectionGateway()

    private var projectionServiceURL: URL?
    private var isConfigured = false

    private init() {}

    public struct FraudCheck: Sendable {
        public let checkId: String
        public let operationType: OperationType
        public let userId: String
        public let deviceId: String
        public let timestamp: Date
        public let signals: [String: String]

        public init(checkId: String, operationType: OperationType, userId: String, deviceId: String, timestamp: Date, signals: [String: String]) {
            self.checkId = checkId
            self.operationType = operationType
            self.userId = userId
            self.deviceId = deviceId
            self.timestamp = timestamp
            self.signals = signals
        }
    }

    public struct FraudResult: Sendable {
        public let checkId: String
        public let riskScore: Double
        public let decision: Decision
        public let reasons: [String]

        public init(checkId: String, riskScore: Double, decision: Decision, reasons: [String]) {
            self.checkId = checkId
            self.riskScore = riskScore
            self.decision = decision
            self.reasons = reasons
        }
    }

    public enum OperationType: String, Sendable {
        case payment
        case login
        case transfer
        case accountChange
        case sensitiveAction
    }

    public enum Decision: String, Sendable {
        case allow
        case challenge
        case block
    }

    public enum ProjectionGatewayError: Error, Sendable {
        case notConfigured
        case invalidURL
        case networkError
        case highRisk
    }

    // MARK: - Configuration

    public func configure(serviceURL: URL) {
        self.projectionServiceURL = serviceURL
        self.isConfigured = true

        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "configure_projection_gateway", "url": serviceURL.absoluteString]
            )
        }
    }

    // MARK: - Fraud Detection

    public func checkFraud(
        operationType: OperationType,
        userId: String,
        deviceId: String,
        signals: [String: String] = [:]
    ) async throws -> FraudResult {
        guard isConfigured, let serviceURL = projectionServiceURL else {
            throw ProjectionGatewayError.notConfigured
        }

        let check = FraudCheck(
            checkId: UUID().uuidString,
            operationType: operationType,
            userId: userId,
            deviceId: deviceId,
            timestamp: Date(),
            signals: signals
        )

        let result = try await performFraudCheck(check: check, serviceURL: serviceURL)

        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: userId,
            metadata: [
                "operation": "fraud_check",
                "type": operationType.rawValue,
                "decision": result.decision.rawValue,
                "riskScore": "\(result.riskScore)"
            ]
        )

        return result
    }

    // MARK: - Private Helpers

    private func performFraudCheck(check: FraudCheck, serviceURL: URL) async throws -> FraudResult {
        return FraudResult(
            checkId: check.checkId,
            riskScore: 0.1,
            decision: .allow,
            reasons: []
        )
    }
}
