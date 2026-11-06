//
//  StepUpAuthenticator.swift
//  SecurityKit
//
//  Satisfaction locale d'une politique de step-up — tâche 3.3.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §12 du prompt d'origine.

import Foundation
import LocalAuthentication
import WaanguCoreKit

/// Satisfait une politique d'authentification renforcée exigée par le backend.
///
/// **Ne décide de rien.** Cette classe ne répond jamais « l'opération est
/// autorisée » : elle produit une `StepUpAttestation` que le backend évalue.
/// La distinction n'est pas rhétorique — sur un appareil compromis, tout
/// mécanisme local répond « succès ». S'il suffisait à autoriser, il suffirait
/// à payer.
///
/// C'est pourquoi aucune méthode ici ne retourne de `Bool` d'autorisation, et
/// pourquoi l'attestation porte la corrélation de l'opération : une attestation
/// obtenue pour un geste anodin ne doit pas pouvoir en couvrir un autre.
public struct StepUpAuthenticator: StepUpAuthenticating {

    private let deviceID: String
    private let logger: AppLogger

    /// Fabrique le contexte d'authentification. Injectable pour les tests, qui ne
    /// peuvent pas présenter une vraie invite biométrique.
    private let contextFactory: @Sendable () -> LAContext

    /// Motif affiché quand l'appelant n'en donne pas — `elevate(to:)`.
    ///
    /// `LAContext.evaluatePolicy` lève une exception Objective-C sur un motif
    /// vide : l'app se fermait dès qu'une entrée du Hub exigeait une élévation
    /// (`requiresStepUp`) ou qu'on activait le code depuis l'accueil. Lu au
    /// moment de l'invite, pour suivre la langue choisie.
    private let defaultReason: @Sendable () -> String

    public init(
        deviceID: String,
        logger: AppLogger,
        contextFactory: @escaping @Sendable () -> LAContext = { LAContext() },
        defaultReason: @escaping @Sendable () -> String = { "Confirm your identity to continue." }
    ) {
        self.deviceID = deviceID
        self.logger = logger
        self.contextFactory = contextFactory
        self.defaultReason = defaultReason
    }

    // MARK: - StepUpAuthenticating (contrat préexistant)

    /// Niveau de la session courante.
    ///
    /// Toujours `.none` : `LocalAuthentication` n'expose aucune notion de session
    /// persistante, et inventer un niveau retenu ferait sauter un step-up que le
    /// backend croit avoir exigé. Le niveau réellement atteint voyage dans
    /// l'attestation, pas dans un état local.
    public var currentLevel: StepUpLevel {
        get async { .none }
    }

    /// Contrat historique. Conservé pour les appelants non financiers.
    public func elevate(to level: StepUpLevel) async throws -> Bool {
        do {
            try await evaluateLocally(level)
            return true
        } catch StepUpError.userCancelled {
            return false
        }
    }

    // MARK: - Satisfaction par attestation

    public func satisfyStepUp(
        level: StepUpLevel,
        reason: String,
        correlationID: CorrelationId,
        deviceID: String
    ) async throws -> StepUpAttestation {

        try await evaluateLocally(level, reason: reason)

        return StepUpAttestation(
            level: level,
            correlationID: correlationID,
            deviceID: deviceID,
            satisfiedAt: Date(),
            // Aucun jeton : `LocalAuthentication` ne produit pas de preuve
            // vérifiable à distance. Le backend doit donc pondérer cette
            // attestation comme une déclaration — d'où l'intérêt d'App Attest
            // pour les montants élevés.
            evidenceToken: nil
        )
    }

    /// Niveaux atteignables sur cet appareil.
    ///
    /// Permet au backend d'exiger un niveau réalisable plutôt que d'échouer après
    /// coup : un appareil sans biométrie enrôlée doit se voir demander autre
    /// chose, pas se voir refuser l'opération.
    public func availableLevels() async -> Set<StepUpLevel> {
        var available: Set<StepUpLevel> = [.none]
        let context = contextFactory()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            available.insert(.pin)
        }
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            available.insert(.biometric)
        }

        // `.biometricAndOTP` et `.fullReauth` exigent une vérification hors bande
        // que seul le backend peut conduire : ne pas les annoncer ici.
        return available
    }

    // MARK: - Évaluation locale

    /// Satisfait localement ce qui peut l'être.
    ///
    /// Les niveaux qui exigent une vérification hors bande lèvent plutôt que de
    /// se satisfaire à moitié : produire une attestation `.biometricAndOTP` après
    /// une simple biométrie serait un mensonge adressé au backend, et c'est
    /// exactement ce qu'un client compromis ferait.
    private func evaluateLocally(_ level: StepUpLevel, reason given: String = "") async throws {
        let trimmed = given.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = defaultReason().trimmingCharacters(in: .whitespacesAndNewlines)
        // Jamais vide : le système refuserait l'invite en fermant l'app.
        let reason = !trimmed.isEmpty ? given : (!fallback.isEmpty ? fallback : "Confirm your identity to continue.")
        switch level {
        case .none:
            return

        case .pin:
            try await evaluate(.deviceOwnerAuthentication, level: level, reason: reason)

        case .biometric:
            try await evaluate(.deviceOwnerAuthenticationWithBiometrics, level: level, reason: reason)

        case .biometricAndOTP, .fullReauth:
            throw StepUpError.levelUnavailable(level)
        }
    }

    // MARK: - Interne

    private func evaluate(
        _ laPolicy: LAPolicy,
        level: StepUpLevel,
        reason: String
    ) async throws {
        let context = contextFactory()
        var error: NSError?

        guard context.canEvaluatePolicy(laPolicy, error: &error) else {
            throw StepUpError.levelUnavailable(level)
        }

        do {
            let success = try await Self.evaluate(context, laPolicy, reason)
            guard success else { throw StepUpError.failed("evaluation_returned_false") }

            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["action": "step_up_satisfied", "level": String(level.rawValue)],
                severity: .info
            )
        } catch let laError as LAError {
            throw Self.map(laError, level: level)
        }
    }

    /// Pont vers l'API à complétion de `LocalAuthentication`.
    ///
    /// La continuation est reprise exactement une fois : `evaluatePolicy` appelle
    /// son bloc une seule fois, et un `CheckedContinuation` repris deux fois
    /// termine le processus.
    private static func evaluate(
        _ context: LAContext,
        _ policy: LAPolicy,
        _ reason: String
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// Traduit une erreur système en erreur métier.
    ///
    /// Toute issue autre qu'un succès explicite est une erreur — il n'existe pas
    /// de chemin par lequel un échec local devienne une autorisation.
    private static func map(_ error: LAError, level: StepUpLevel) -> StepUpError {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return .userCancelled
        case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
            return .levelUnavailable(level)
        case .biometryLockout:
            return .lockedOut
        default:
            return .failed(String(describing: error.code))
        }
    }
}
