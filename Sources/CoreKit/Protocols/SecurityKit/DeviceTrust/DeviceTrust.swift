// MARK: - DeviceTrust.swift
// Module: CoreKit
// Contracts for Device Trust: device binding, runtime protection,
// device integrity, step-up authentication, passkeys, session risk,
// and the aggregated trust verdict.

import Foundation

// MARK: - Device Binding

/// Manages a Secure Enclave key pair bound to this device.
/// The private key never leaves the hardware.
public protocol DeviceBindingProviding: Sendable {

    /// `true` if a Secure Enclave key pair exists for the current account.
    var isBound: Bool { get async }

    /// Generates a key pair in the Secure Enclave and returns the public key (DER-encoded).
    func bind() async throws -> Data

    /// Signs an arbitrary challenge with the Secure Enclave private key.
    func sign(challenge: Data) async throws -> Data

    /// Deletes the key pair (e.g. on logout or account removal).
    func unbind() async throws
}

// MARK: - Runtime Protection (RASP)

/// Threat categories detected at runtime.
public enum EnvironmentThreat: String, Sendable, CaseIterable {
    case hookingDetected
    case debuggerAttached
    case binaryTampered
    case screenCaptureActive
    case keyloggerSuspected
    case reverseEngineeringTool
}

/// Monitors the runtime environment for active threats (hooking, debugging, tampering…).
public protocol RuntimeProtectionProviding: Sendable {

    /// One-shot evaluation of threats active right now.
    func detectThreats() async -> Set<EnvironmentThreat>

    /// Continuous stream of threat-set changes.
    var threatStream: AsyncStream<Set<EnvironmentThreat>> { get }
}

// MARK: - Device Integrity (Jailbreak + Emulator)

/// Result of a device integrity evaluation.
public struct DeviceIntegrityStatus: Sendable, Equatable {

    /// `true` if jailbreak indicators were found.
    public let isJailbroken: Bool

    /// `true` if the app is running on a simulator or emulator.
    public let isEmulator: Bool

    /// Composite score: 0.0 (fully compromised) → 1.0 (healthy).
    public let integrityScore: Double

    /// Human-readable signals for observability logging (never shown to user).
    public let signals: [String]

    public init(
        isJailbroken: Bool,
        isEmulator: Bool,
        integrityScore: Double,
        signals: [String]
    ) {
        self.isJailbroken = isJailbroken
        self.isEmulator = isEmulator
        self.integrityScore = integrityScore
        self.signals = signals
    }
}

/// Evaluates the physical integrity of the device (jailbreak + emulator checks).
public protocol DeviceIntegrityProviding: Sendable {
    func evaluate() async -> DeviceIntegrityStatus
}

// MARK: - Step-Up Authentication

/// Increasing levels of authentication assurance.
/// - Note: `Codable` ajouté par le Bloc 1 — `StepUpAttestation` doit pouvoir
///   traverser le réseau et survivre au disque. Un enum à valeur brute ne
///   conforme pas automatiquement, il faut le déclarer.
public enum StepUpLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    /// No authentication required.
    case none = 0
    /// PIN or password.
    case pin = 1
    /// Biometric (Face ID / Touch ID).
    case biometric = 2
    /// Biometric + OTP (SMS or push).
    case biometricAndOTP = 3
    /// Full re-authentication (credentials + biometric + OTP).
    case fullReauth = 4

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Triggers contextual re-authentication when an operation requires
/// a higher assurance level than the current session provides.
///
/// - Note: Pour une opération **financière**, utiliser
///   `satisfyStepUp(level:reason:correlationID:deviceID:)` — déclaré dans
///   `Protocols/Finance/StepUpAuthenticating.swift`. Il rend une
///   `StepUpAttestation` corrélée à l'opération, là où `elevate(to:)` ne rend
///   qu'un booléen produit localement, qu'un appareil compromis met à `true`
///   sans effort. Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §12.
public protocol StepUpAuthenticating: Sendable {

    /// The assurance level established by the most recent authentication event.
    var currentLevel: StepUpLevel { get async }

    /// Attempts to elevate the session to the requested level.
    /// Returns `true` on success, `false` if the user cancels.
    /// Throws on system errors (biometry unavailable, etc.).
    ///
    /// - Warning: Ne constitue **jamais** une autorisation financière. Le
    ///   booléen ne quitte pas l'appareil et n'est corrélé à aucune opération :
    ///   rien n'empêche de le réutiliser pour en couvrir une autre.
    func elevate(to level: StepUpLevel) async throws -> Bool

    /// Satisfait une politique de step-up pour **une** opération financière.
    ///
    /// Exigence du protocole, et non simple extension : déclarée seulement en
    /// extension, l'appel à travers `any StepUpAuthenticating` — la forme sous
    /// laquelle tous les écrans financiers le tiennent — prenait toujours le
    /// repli, qui passe par `elevate(to:)` **sans motif**. L'implémentation
    /// réelle n'était jamais appelée : l'invite système ne montrait jamais le
    /// motif de l'écran. Le repli reste fourni par l'extension
    /// (`Protocols/Finance/Shared/StepUpAuthenticating.swift`).
    func satisfyStepUp(
        level: StepUpLevel,
        reason: String,
        correlationID: CorrelationId,
        deviceID: String
    ) async throws -> StepUpAttestation
}

// MARK: - Passkeys (WebAuthn / FIDO2)

/// Handles passkey registration and authentication via ASAuthorizationServices.
public protocol PasskeyAuthenticating: Sendable {

    /// `true` if the current device and OS support passkeys.
    var isSupported: Bool { get }

    /// Creates and registers a new passkey for the given user.
    /// Returns the attestation object to send to the server.
    func register(for userId: String, challenge: Data) async throws -> Data

    /// Authenticates with an existing passkey.
    /// Returns the assertion object to send to the server.
    func authenticate(challenge: Data) async throws -> Data
}

// MARK: - Session Risk

/// Individual risk signal detected during session evaluation.
public enum RiskSignal: String, Sendable, CaseIterable {
    case unusualLocation
    case velocityAnomaly
    case unusualAmount
    case unusualTime
    case newDevice
    case deviceIntegrityFailed
    case raspThreatDetected
}

/// Snapshot of a session risk evaluation.
public struct SessionRiskAssessment: Sendable, Equatable {

    /// 0.0 (safe) → 1.0 (critical risk).
    public let score: Double

    /// Step-up level the system recommends based on the score.
    public let requiredStepUp: StepUpLevel

    /// Signals that contributed to the score.
    public let signals: [RiskSignal]

    /// When this assessment was computed.
    public let evaluatedAt: Date

    public init(
        score: Double,
        requiredStepUp: StepUpLevel,
        signals: [RiskSignal],
        evaluatedAt: Date
    ) {
        self.score = score
        self.requiredStepUp = requiredStepUp
        self.signals = signals
        self.evaluatedAt = evaluatedAt
    }
}

/// Continuously evaluates the risk level of the active session
/// by combining device health, location, velocity, and behavioral signals.
public protocol SessionRiskEvaluating: Sendable {

    /// One-shot evaluation for a specific operation.
    /// - Parameters:
    ///   - operation: identifier of the operation being attempted (e.g. "transfer", "card_reveal").
    ///   - amount: optional monetary amount for amount-based risk scoring.
    func evaluate(for operation: String, amount: Decimal?) async -> SessionRiskAssessment

    /// Continuous stream of risk re-evaluations during the session.
    var riskStream: AsyncStream<SessionRiskAssessment> { get }
}

// MARK: - Device Trust (Aggregated Verdict)

/// Aggregated verdict combining all device trust signals.
public struct DeviceTrustVerdict: Sendable, Equatable {

    /// Overall trust decision: `true` means the device is considered safe
    /// for the current operation.
    public let isTrusted: Bool

    /// Detailed integrity status (jailbreak, emulator).
    public let deviceIntegrity: DeviceIntegrityStatus

    /// Runtime threats currently active.
    public let activeThreats: Set<EnvironmentThreat>

    /// Session risk assessment at evaluation time.
    public let sessionRisk: SessionRiskAssessment

    /// `true` if a Secure Enclave key pair is bound to this device.
    public let isBound: Bool

    /// When this verdict was computed.
    public let evaluatedAt: Date

    public init(
        isTrusted: Bool,
        deviceIntegrity: DeviceIntegrityStatus,
        activeThreats: Set<EnvironmentThreat>,
        sessionRisk: SessionRiskAssessment,
        isBound: Bool,
        evaluatedAt: Date
    ) {
        self.isTrusted = isTrusted
        self.deviceIntegrity = deviceIntegrity
        self.activeThreats = activeThreats
        self.sessionRisk = sessionRisk
        self.isBound = isBound
        self.evaluatedAt = evaluatedAt
    }
}

/// Aggregates all device trust signals (binding, integrity, RASP, session risk)
/// into a single verdict, and produces cryptographic attestations
/// to attach to sensitive API requests.
public protocol DeviceTrustProviding: Sendable {

    /// Computes a full trust verdict by combining all available signals.
    func evaluate() async -> DeviceTrustVerdict

    /// Produces a Secure Enclave signature over the given challenge,
    /// to be sent as `X-Device-Signature` on sensitive requests.
    func attestation(for challenge: Data) async throws -> Data
}
