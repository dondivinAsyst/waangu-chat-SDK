//
//  SessionRiskEvaluator.swift
//  SecurityKit
//
//  Premier conformeur de `SessionRiskEvaluating` — tâche 11.6b.
//
//  Le contrat existait dans `CoreKit/.../DeviceTrust/DeviceTrust.swift` depuis
//  avant le Bloc 1, sans implémentation. Il est taillé pour la finance : il prend
//  un montant, `RiskSignal` contient `unusualAmount`, et `SessionRiskAssessment`
//  porte `requiredStepUp`. Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §1.4b.

import Foundation
import WaanguCoreKit

/// Évalue le risque d'une opération à partir des signaux locaux disponibles.
///
/// **Ne décide jamais seul.** Son résultat ne peut qu'**élever** l'exigence
/// d'authentification décidée par le backend, jamais l'abaisser — voir
/// `StepUpRequirement`. Un client compromis qui renverrait « risque nul »
/// n'obtiendrait donc rien : au pire il annule sa propre prudence supplémentaire,
/// jamais celle du serveur.
///
/// C'est ce qui rend acceptable de faire tourner une évaluation de risque sur
/// l'appareil qu'elle est censée surveiller.
public actor SessionRiskEvaluator: SessionRiskEvaluating {

    private let integrity: (any DeviceIntegrityProviding)?
    private let runtimeProtection: (any RuntimeProtectionProviding)?
    private let thresholds: RiskThresholds
    private let logger: AppLogger

    /// Flux des réévaluations.
    ///
    /// `nonisolated let` : le protocole l'expose en accès synchrone, et un
    /// `AsyncStream` d'élément `Sendable` l'est lui-même. Le construire dans
    /// l'initialiseur évite un `lazy var` sur un acteur, qui exigerait `await`
    /// là où le contrat n'en laisse pas la place.
    public nonisolated let riskStream: AsyncStream<SessionRiskAssessment>
    private nonisolated let continuation: AsyncStream<SessionRiskAssessment>.Continuation

    public init(
        integrity: (any DeviceIntegrityProviding)? = nil,
        runtimeProtection: (any RuntimeProtectionProviding)? = nil,
        thresholds: RiskThresholds = .conservative,
        logger: AppLogger
    ) {
        self.integrity = integrity
        self.runtimeProtection = runtimeProtection
        self.thresholds = thresholds
        self.logger = logger

        var capturedContinuation: AsyncStream<SessionRiskAssessment>.Continuation!
        self.riskStream = AsyncStream { capturedContinuation = $0 }
        self.continuation = capturedContinuation
    }

    // MARK: - SessionRiskEvaluating

    public func evaluate(for operation: String, amount: Decimal?) async -> SessionRiskAssessment {
        var signals: [RiskSignal] = []
        var score = 0.0

        // ── Intégrité de l'appareil ───────────────────────────
        if let integrity {
            let status = await integrity.evaluate()
            if status.isJailbroken {
                signals.append(.deviceIntegrityFailed)
                score += thresholds.jailbreakWeight
            }
            // L'émulateur ne monte pas le score : c'est l'environnement normal du
            // développement et des tests. Le traiter comme une menace rendrait
            // toute opération financière intestable, ce qui pousse à désactiver
            // le contrôle — donc à le perdre en production aussi.
        }

        // ── Menaces à l'exécution ─────────────────────────────
        if let runtimeProtection {
            let threats = await runtimeProtection.detectThreats()
            let serious = threats.subtracting([.screenCaptureActive])
            if !serious.isEmpty {
                signals.append(.raspThreatDetected)
                score += thresholds.raspWeight
            }
        }

        // ── Montant ───────────────────────────────────────────
        if let amount, amount >= thresholds.unusualAmount {
            signals.append(.unusualAmount)
            score += thresholds.amountWeight
        }

        let bounded = min(max(score, 0), 1)
        let assessment = SessionRiskAssessment(
            score: bounded,
            requiredStepUp: level(for: bounded),
            signals: signals,
            evaluatedAt: Date()
        )

        if !signals.isEmpty {
            await logger.log(
                "Risque session \(operation): score=\(bounded) signaux=\(signals.map(\.rawValue))",
                level: .info
            )
        }

        continuation.yield(assessment)
        return assessment
    }

    // MARK: - Interne

    /// Niveau recommandé pour un score.
    ///
    /// Recommandation, pas décision : `StepUpRequirement` ne s'en sert que pour
    /// élever l'exigence backend.
    private func level(for score: Double) -> StepUpLevel {
        switch score {
        case ..<0.25:  return .none
        case ..<0.5:   return .pin
        case ..<0.75:  return .biometric
        default:       return .biometricAndOTP
        }
    }
}

// MARK: - Seuils

/// Pondérations et seuils du score de risque.
///
/// **BACKEND CONTRACT REQUIRED.** Les valeurs par défaut sont prudentes mais
/// arbitraires : un seuil de montant dépend du pays, de la devise et du profil de
/// l'utilisateur. 500 000 BIF et 500 CAD ne sont pas le même événement. Les
/// calibrer côté client, c'est se tromper dans les trois pays à la fois.
///
/// Elles ne servent qu'à *ajouter* de la prudence : sous-estimer le risque ne
/// retire jamais l'exigence backend.
public struct RiskThresholds: Sendable, Equatable {

    public let unusualAmount: Decimal
    public let amountWeight: Double
    public let jailbreakWeight: Double
    public let raspWeight: Double

    public init(
        unusualAmount: Decimal,
        amountWeight: Double,
        jailbreakWeight: Double,
        raspWeight: Double
    ) {
        self.unusualAmount = unusualAmount
        self.amountWeight = amountWeight
        self.jailbreakWeight = jailbreakWeight
        self.raspWeight = raspWeight
    }

    /// Défaut prudent : un appareil jailbreaké suffit à exiger le niveau maximal.
    public static let conservative = RiskThresholds(
        unusualAmount: 100_000,
        amountWeight: 0.3,
        jailbreakWeight: 0.8,
        raspWeight: 0.8
    )
}
