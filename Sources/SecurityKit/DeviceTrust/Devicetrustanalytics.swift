// MARK: - DeviceTrustAnalytics.swift
// Module: SecurityKit
// Typed analytics events for Device Trust components.
// Conforms to AnalyticsEvent (CoreKit) for type-safe logging
// via AnalyticsProtocol.

import Foundation
import WaanguCoreKit

// MARK: - Analytics Events

/// All analytics events emitted by the Device Trust subsystem.
///
/// Usage:
/// ```swift
/// analytics.log(DeviceTrustAnalyticsEvent.deviceBound(accountId: "user_roland"))
/// analytics.log(DeviceTrustAnalyticsEvent.raspThreatDetected(threats: [.hookingDetected]))
/// ```
public enum DeviceTrustAnalyticsEvent: AnalyticsEvent, Sendable {

    // MARK: Device Binding

    /// A Secure Enclave key pair was created for an account.
    case deviceBound(accountId: String)

    /// An existing Secure Enclave key pair was removed.
    case deviceUnbound(accountId: String)

    /// A challenge was signed with the Secure Enclave private key.
    case challengeSigned(accountId: String)

    /// A Secure Enclave operation failed.
    case bindingFailed(accountId: String, reason: String)

    // MARK: RASP

    /// One or more runtime threats were detected.
    case raspThreatDetected(threats: Set<EnvironmentThreat>)

    /// All previously active threats have been cleared.
    case raspThreatsCleared

    /// Continuous monitoring was started.
    case raspMonitoringStarted

    /// Continuous monitoring was stopped.
    case raspMonitoringStopped

    // MARK: Device Integrity

    /// A device integrity evaluation completed.
    case integrityEvaluated(
        isJailbroken: Bool,
        isEmulator: Bool,
        score: Double
    )

    // MARK: Step-Up

    /// A step-up authentication was requested.
    case stepUpRequested(operation: String, level: StepUpLevel)

    /// A step-up authentication succeeded.
    case stepUpSucceeded(operation: String, level: StepUpLevel)

    /// A step-up authentication was cancelled by the user.
    case stepUpCancelled(operation: String, level: StepUpLevel)

    /// A step-up authentication failed (system error, not user cancel).
    case stepUpFailed(operation: String, level: StepUpLevel, reason: String)

    // MARK: Passkeys

    /// A passkey was registered for an account.
    case passkeyRegistered(userId: String)

    /// A passkey authentication succeeded.
    case passkeyAuthenticated

    /// A passkey operation failed.
    case passkeyFailed(reason: String)

    // MARK: Session Risk

    /// A session risk evaluation completed.
    case sessionRiskEvaluated(
        operation: String,
        score: Double,
        signals: [RiskSignal],
        requiredStepUp: StepUpLevel
    )

    // MARK: Trust Verdict

    /// An aggregated trust verdict was computed.
    case trustVerdictEvaluated(isTrusted: Bool, score: Double, threatCount: Int)

    /// A request was blocked because the device was not trusted.
    case requestBlockedByTrust(operation: String, reason: String)

    // MARK: - AnalyticsEvent Conformance

    public var name: String {
        switch self {
        case .deviceBound:             "device_trust_bound"
        case .deviceUnbound:           "device_trust_unbound"
        case .challengeSigned:         "device_trust_challenge_signed"
        case .bindingFailed:           "device_trust_binding_failed"
        case .raspThreatDetected:      "device_trust_rasp_threat"
        case .raspThreatsCleared:      "device_trust_rasp_cleared"
        case .raspMonitoringStarted:   "device_trust_rasp_started"
        case .raspMonitoringStopped:   "device_trust_rasp_stopped"
        case .integrityEvaluated:      "device_trust_integrity"
        case .stepUpRequested:         "device_trust_stepup_requested"
        case .stepUpSucceeded:         "device_trust_stepup_succeeded"
        case .stepUpCancelled:         "device_trust_stepup_cancelled"
        case .stepUpFailed:            "device_trust_stepup_failed"
        case .passkeyRegistered:       "device_trust_passkey_registered"
        case .passkeyAuthenticated:    "device_trust_passkey_authenticated"
        case .passkeyFailed:           "device_trust_passkey_failed"
        case .sessionRiskEvaluated:    "device_trust_session_risk"
        case .trustVerdictEvaluated:   "device_trust_verdict"
        case .requestBlockedByTrust:   "device_trust_request_blocked"
        }
    }

    public var parameters: [String: Any]? {
        switch self {

        case .deviceBound(let accountId):
            ["account_id": accountId]

        case .deviceUnbound(let accountId):
            ["account_id": accountId]

        case .challengeSigned(let accountId):
            ["account_id": accountId]

        case .bindingFailed(let accountId, let reason):
            ["account_id": accountId, "reason": reason]

        case .raspThreatDetected(let threats):
            ["threats": threats.map(\.rawValue).sorted(), "count": threats.count]

        case .raspThreatsCleared:
            nil

        case .raspMonitoringStarted:
            nil

        case .raspMonitoringStopped:
            nil

        case .integrityEvaluated(let isJailbroken, let isEmulator, let score):
            [
                "is_jailbroken": isJailbroken,
                "is_emulator": isEmulator,
                "integrity_score": score
            ]

        case .stepUpRequested(let operation, let level):
            ["operation": operation, "level": level.rawValue]

        case .stepUpSucceeded(let operation, let level):
            ["operation": operation, "level": level.rawValue]

        case .stepUpCancelled(let operation, let level):
            ["operation": operation, "level": level.rawValue]

        case .stepUpFailed(let operation, let level, let reason):
            ["operation": operation, "level": level.rawValue, "reason": reason]

        case .passkeyRegistered(let userId):
            ["user_id": userId]

        case .passkeyAuthenticated:
            nil

        case .passkeyFailed(let reason):
            ["reason": reason]

        case .sessionRiskEvaluated(let operation, let score, let signals, let requiredStepUp):
            [
                "operation": operation,
                "score": score,
                "signals": signals.map(\.rawValue),
                "required_step_up": requiredStepUp.rawValue
            ]

        case .trustVerdictEvaluated(let isTrusted, let score, let threatCount):
            [
                "is_trusted": isTrusted,
                "score": score,
                "threat_count": threatCount
            ]

        case .requestBlockedByTrust(let operation, let reason):
            ["operation": operation, "reason": reason]
        }
    }
}

// MARK: - Crash Reporter Breadcrumb Helpers

/// Convenience helpers for consistent Device Trust breadcrumbs
/// in crash reports (Sentry / Crashlytics).
public enum DeviceTrustBreadcrumbs {

    private static let category = "device_trust"

    public static func bindingPerformed(
        _ reporter: any CrashReporterProtocol,
        accountId: String
    ) {
        reporter.addBreadcrumb(
            category: category,
            message: "Device bound for \(accountId)",
            level: .info,
            data: nil
        )
    }

    public static func threatDetected(
        _ reporter: any CrashReporterProtocol,
        threats: Set<EnvironmentThreat>
    ) {
        reporter.addBreadcrumb(
            category: category,
            message: "RASP threats: \(threats.map(\.rawValue).sorted().joined(separator: ", "))",
            level: .warning,
            data: ["count": threats.count]
        )
    }

    public static func integrityCompromised(
        _ reporter: any CrashReporterProtocol,
        status: DeviceIntegrityStatus
    ) {
        reporter.addBreadcrumb(
            category: category,
            message: "Integrity compromised — jailbreak: \(status.isJailbroken), emulator: \(status.isEmulator)",
            level: .error,
            data: ["score": status.integrityScore, "signals": status.signals]
        )
    }

    public static func verdictUntrusted(
        _ reporter: any CrashReporterProtocol,
        verdict: DeviceTrustVerdict
    ) {
        reporter.captureMessage(
            "Device trust verdict: UNTRUSTED (score: \(verdict.sessionRisk.score))",
            level: .error
        )
        reporter.setContext(key: "device_trust", value: [
            "is_trusted": verdict.isTrusted,
            "is_bound": verdict.isBound,
            "is_jailbroken": verdict.deviceIntegrity.isJailbroken,
            "is_emulator": verdict.deviceIntegrity.isEmulator,
            "integrity_score": verdict.deviceIntegrity.integrityScore,
            "active_threats": verdict.activeThreats.map(\.rawValue),
            "risk_score": verdict.sessionRisk.score,
            "risk_signals": verdict.sessionRisk.signals.map(\.rawValue)
        ])
    }

    public static func stepUpTriggered(
        _ reporter: any CrashReporterProtocol,
        operation: String,
        level: StepUpLevel
    ) {
        reporter.addBreadcrumb(
            category: category,
            message: "Step-up \(level) for \(operation)",
            level: .info,
            data: nil
        )
    }
}
