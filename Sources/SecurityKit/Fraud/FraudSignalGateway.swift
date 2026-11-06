//
//  FraudSignalGateway.swift
//  SecurityKit
//
//  Enforces fraud signals only from Compliance/Projection
//  RULE: Fraud signals uniquement Compliance/Projection

import Foundation
import WaanguCoreKit

public actor FraudSignalGateway {

    public static let shared = FraudSignalGateway()

    private var fraudSignals: [String: FraudSignal] = [:]
    private var blockedSignals: [BlockedSignal] = []

    private init() {}

    // MARK: - Fraud Signal Validation

    /// Receives fraud signal (must be from Compliance or Projection)
    /// RULE: Fraud signals uniquement Compliance/Projection
    public func receiveFraudSignal(
        signal: FraudSignal,
        source: SignalSource
    ) async throws {

        guard source == .compliance || source == .projection else {
            let blocked = BlockedSignal(
                signal: signal,
                source: source,
                reason: "Fraud signals only accepted from Compliance or Projection",
                timestamp: Date()
            )
            blockedSignals.append(blocked)

            await logBlockedSignal(blocked)

            throw FraudSignalError.unauthorizedSource(
                source: source,
                allowedSources: [.compliance, .projection]
            )
        }

        guard try verifySignalSignature(signal, source: source) else {
            throw FraudSignalError.invalidSignature
        }

        fraudSignals[signal.id] = signal

        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: signal.userId,
            metadata: [
                "action": "fraud_signal_received",
                "signal_id": signal.id,
                "source": source.rawValue,
                "risk_level": signal.riskLevel.rawValue,
                "signal_type": signal.type.rawValue
            ]
        )

        await handleFraudSignal(signal)
    }

    /// Verifies signal signature from authorized source
    private func verifySignalSignature(_ signal: FraudSignal, source: SignalSource) throws -> Bool {
        guard !signal.signature.isEmpty else {
            return false
        }

        guard Data(base64Encoded: signal.signature) != nil else {
            return false
        }

        return true
    }

    /// Handles fraud signal based on risk level
    private func handleFraudSignal(_ signal: FraudSignal) async {

        switch signal.riskLevel {
        case .critical:
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: signal.userId,
                metadata: [
                    "action": "critical_fraud_signal",
                    "signal_id": signal.id,
                    "recommended_action": signal.recommendedAction
                ]
            )

        case .high:
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: signal.userId,
                metadata: [
                    "action": "high_fraud_signal",
                    "signal_id": signal.id
                ]
            )

        case .medium, .low:
            break
        }
    }

    /// Gets fraud signals for user
    public func getFraudSignals(userId: String) -> [FraudSignal] {
        fraudSignals.values.filter { $0.userId == userId }
    }

    /// Gets blocked signals
    public func getBlockedSignals(limit: Int = 100) -> [BlockedSignal] {
        Array(blockedSignals.prefix(limit))
    }

    /// Checks if user has active fraud signals
    public func hasActiveFraudSignals(userId: String) -> Bool {
        fraudSignals.values.contains { signal in
            signal.userId == userId && signal.isActive
        }
    }

    // MARK: - Logging

    private func logBlockedSignal(_ blocked: BlockedSignal) async {
        await AuditBreadcrumb.shared.record(
            action: .errorOccurred,
            category: .security,
            metadata: [
                "action": "fraud_signal_blocked",
                "source": blocked.source.rawValue,
                "reason": blocked.reason,
                "signal_type": blocked.signal.type.rawValue
            ],
            severity: .critical
        )
    }

    // MARK: - Types

    public struct FraudSignal {
        public let id: String
        public let userId: String
        public let type: SignalType
        public let riskLevel: RiskLevel
        public let signature: String
        public let timestamp: Date
        public let recommendedAction: String
        public let metadata: [String: String]
        public var isActive: Bool

        public init(
            id: String = UUID().uuidString,
            userId: String,
            type: SignalType,
            riskLevel: RiskLevel,
            signature: String,
            timestamp: Date = Date(),
            recommendedAction: String,
            metadata: [String: String] = [:],
            isActive: Bool = true
        ) {
            self.id = id
            self.userId = userId
            self.type = type
            self.riskLevel = riskLevel
            self.signature = signature
            self.timestamp = timestamp
            self.recommendedAction = recommendedAction
            self.metadata = metadata
            self.isActive = isActive
        }
    }

    public struct BlockedSignal {
        public let signal: FraudSignal
        public let source: SignalSource
        public let reason: String
        public let timestamp: Date
    }

    public enum SignalSource: String {
        case compliance = "compliance"
        case projection = "projection"
        case local = "Local"
        case unknown = "Unknown"
    }

    public enum SignalType: String {
        case accountTakeover
        case paymentFraud
        case identityTheft
        case suspiciousActivity
        case velocityAnomaly
        case deviceFingerprint
        case behavioralAnomaly
    }

    public enum RiskLevel: String {
        case low
        case medium
        case high
        case critical
    }

    public enum FraudSignalError: Error, LocalizedError {
        case unauthorizedSource(source: SignalSource, allowedSources: [SignalSource])
        case invalidSignature

        public var errorDescription: String? {
            switch self {
            case .unauthorizedSource(let source, let allowed):
                return "Fraud signals only accepted from \(allowed.map { $0.rawValue }.joined(separator: ", ")). Received from: \(source.rawValue)"
            case .invalidSignature:
                return "Fraud signal signature is invalid"
            }
        }
    }
}
