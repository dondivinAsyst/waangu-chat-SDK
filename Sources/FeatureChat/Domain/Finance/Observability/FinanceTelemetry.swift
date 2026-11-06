//
//  FinanceTelemetry.swift
//  FeatureChat
//
//  Événements d'observabilité financière — tâches 9.1 à 9.4.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §10.

import Foundation
import WaanguCoreKit

/// Émet les événements financiers.
///
/// **L'analytics n'est jamais une source de vérité financière.** Ces événements
/// servent à détecter des anomalies, pas à reconstituer un état : un événement
/// perdu ou échantillonné ne doit avoir aucune conséquence sur ce que
/// l'utilisateur voit.
public struct FinanceTelemetry: Sendable {

    /// Noms d'événements. Valeurs fermées — jamais une chaîne construite depuis
    /// une réponse serveur, qui ferait exploser la cardinalité du dashboard.
    public enum Event: String, Sendable, CaseIterable {
        case intentCreated        = "finance.intent.created"
        case intentConfirmed      = "finance.intent.confirmed"
        case intentSubmitted      = "finance.intent.submitted"
        case intentPending        = "finance.intent.pending"
        case intentConfirmedServer = "finance.intent.confirmed_server"
        case intentFailed         = "finance.intent.failed"
        case intentUnknown        = "finance.intent.unknown"
        case intentReconciled     = "finance.intent.reconciled"
        case intentRetry          = "finance.intent.retry"
        case intentCancelled      = "finance.intent.cancelled"
        case securityStepUp       = "finance.security.step_up"
        case complianceBlocked    = "finance.compliance.blocked"
        case cardRendered         = "finance.card.rendered"

        /// Une révision reçue a été rejetée parce qu'elle n'était pas plus récente.
        ///
        /// **L'alerte clé du Bloc 1.** Un taux non nul révèle un désordre
        /// d'événements côté transport — un défaut qui, sans cette mesure, ne se
        /// manifeste que par des statuts qui « reculent » à l'écran, sans trace.
        case eventVersionRejected = "finance.event.version_rejected"
    }

    private let analytics: any AnalyticsProtocol
    private let logger: any AppLoggerProtocol

    public init(analytics: any AnalyticsProtocol, logger: any AppLoggerProtocol) {
        self.analytics = analytics
        self.logger = logger
    }

    // MARK: - Émission

    /// Émet un événement à partir d'un contexte financier.
    ///
    /// Les paramètres viennent de `FinanceLogContext.fields`, dont l'identifiant
    /// d'objet est déjà haché. Aucun chemin de ce fichier ne peut donc publier un
    /// identifiant brut, un montant ou une contrepartie.
    public func record(_ event: Event, context: FinanceLogContext) async {
        analytics.logEvent(event.rawValue, parameters: context.fields)
        await logger.log("\(event.rawValue) \(context)", level: level(for: event))
    }

    /// Émet un rejet de révision, avec les deux versions en cause.
    public func recordStaleRejected(
        reference: FinancialReference,
        currentVersion: Int
    ) async {
        var context = FinanceLogContext(reference: reference, operation: "version_guard").fields
        context["rejected_version"] = String(reference.version)
        context["current_version"] = String(currentVersion)

        analytics.logEvent(Event.eventVersionRejected.rawValue, parameters: context)
        await logger.log(
            "Révision périmée rejetée v\(reference.version) ≤ v\(currentVersion)",
            level: .warning
        )
    }

    /// Émet un blocage Compliance, sans le motif réglementaire détaillé.
    public func recordComplianceBlocked(
        context: FinanceLogContext,
        displayReason: String?
    ) async {
        var fields = context.fields
        // Le motif affichable est publié ; le détail réglementaire ne l'est
        // jamais — il relève de la décision de Compliance, pas de la télémétrie.
        if let displayReason { fields["display_reason"] = displayReason }
        analytics.logEvent(Event.complianceBlocked.rawValue, parameters: fields)
        await logger.log("Compliance a bloqué l'opération — \(context)", level: .warning)
    }

    // MARK: - Niveaux

    /// Niveau de log associé à un événement.
    ///
    /// `intentUnknown` et `eventVersionRejected` sont en `warning` : ce sont les
    /// deux signaux sur lesquels une alerte doit être configurée (§9.4). Les
    /// noyer en `info` les rendrait invisibles dans le volume normal.
    private func level(for event: Event) -> LogLevel {
        switch event {
        case .intentUnknown, .eventVersionRejected, .complianceBlocked:
            return .warning
        case .intentFailed:
            return .error
        default:
            return .info
        }
    }
}
