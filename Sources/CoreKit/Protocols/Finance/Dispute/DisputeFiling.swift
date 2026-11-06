//
//  DisputeFiling.swift
//  CoreKit
//
//  Ouverture d'un litige — Bloc 3, chapitre 25.
//
//  **BACKEND CONTRACT REQUIRED** — `POST /v1/disputes`, `/evidence`, `/reopen`.
//

import Foundation

/// Dépose et suit un litige sur une opération financière.
public protocol DisputeFiling: Sendable {

    func file(_ draft: DisputeDraft,
              idempotency: IdempotencyContext) async -> Result<FinancialReference, FinanceError>

    /// Preuves autorisées pour ce motif, **décidées par le backend**.
    ///
    /// Le client ne les devine pas : ce qui constitue une preuve recevable
    /// dépend du rail, du partenaire et de la juridiction.
    func allowedEvidence(for reason: DisputeReason) async -> Result<[EvidenceKind], FinanceError>

    /// `GET /disputes/{id}` et `/timeline` — où en est le dossier. Un litige se
    /// suit par ses propres routes : `/objects/` ne connaît que les paiements.
    func follow(disputeID: String) async -> Result<DisputeStatusSnapshot, FinanceError>

    /// `GET /disputes/taxonomy` — les seules catégories qu'un litige peut porter
    /// (`CF_048`). Le client n'en invente aucune.
    func categories() async -> Result<[String], FinanceError>
}

public extension DisputeFiling {
    /// Sans lecture de la taxonomie : aucune catégorie à proposer.
    func categories() async -> Result<[String], FinanceError> {
        .failure(.capabilityUnavailable)
    }

    /// Sans lecture du dossier : rien à suivre.
    func follow(disputeID: String) async -> Result<DisputeStatusSnapshot, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

/// Le dossier, tel que le serveur l'a rendu — rien n'est inventé ici.
public struct DisputeStatusSnapshot: Sendable, Hashable {
    public let disputeID: String
    /// `OPEN`, `CLOSED`… : le mot du serveur.
    public let status: String
    public let category: String?
    public let priority: String?
    public let firstResponseDueAt: Date?
    public let resolveDueAt: Date?
    public let closedAt: Date?
    public let timeline: [DisputeTimelineStep]

    public init(disputeID: String, status: String, category: String? = nil, priority: String? = nil,
                firstResponseDueAt: Date? = nil, resolveDueAt: Date? = nil, closedAt: Date? = nil,
                timeline: [DisputeTimelineStep] = []) {
        self.disputeID = disputeID
        self.status = status
        self.category = category
        self.priority = priority
        self.firstResponseDueAt = firstResponseDueAt
        self.resolveDueAt = resolveDueAt
        self.closedAt = closedAt
        self.timeline = timeline
    }
}

/// Une étape de la frise : `FCO_CREATED`, `QUOTE`, `FINALITY`…
public struct DisputeTimelineStep: Sendable, Hashable {
    public let step: String
    public let value: String?

    public init(step: String, value: String?) {
        self.step = step
        self.value = value
    }
}

// MARK: - Motifs

/// Les dix motifs du chapitre 25.
public enum DisputeReason: String, Codable, Sendable, CaseIterable {
    case fraud                = "FRAUD"
    case unknownPayment       = "UNKNOWN_PAYMENT"
    case wrongRecipient       = "WRONG_RECIPIENT"
    case wrongAmount          = "WRONG_AMOUNT"
    case serviceNotDelivered  = "SERVICE_NOT_DELIVERED"
    case rechargeIssue        = "RECHARGE_ISSUE"
    case cashIssue            = "CASH_ISSUE"
    case duplicateDebit       = "DUPLICATE_DEBIT"
    case billIssue            = "BILL_ISSUE"
    case merchantIssue        = "MERCHANT_ISSUE"
}

public enum EvidenceKind: String, Codable, Sendable, CaseIterable {
    case text, photo, document, screenshot
}

// MARK: - Brouillon

/// Un litige en préparation, **prérempli** avec ce que le client sait déjà.
///
/// L'exigence du chapitre 25 est explicite : « l'utilisateur ne doit pas devoir
/// recopier manuellement toutes les informations ». Quelqu'un qui vient de subir
/// un débit qu'il conteste est la dernière personne à qui demander de retranscrire
/// un identifiant de corrélation à la main.
///
/// C'est le seul point du chapitre 25 qui ne dépend d'aucun backend nouveau : le
/// socle porte déjà tout ce qu'il faut.
public struct DisputeDraft: Sendable, Hashable, Codable {

    public let reference: FinancialReference
    /// Motif local d'un ancien parcours. Optionnel : la catégorie du serveur le remplace.
    public let reason: DisputeReason?

    /// La catégorie **du serveur** (`GET /disputes/taxonomy`), envoyée telle quelle.
    public let category: String?

    /// Description libre. Le **seul** champ que l'utilisateur remplit.
    public let description: String

    /// Corrélation de l'opération contestée, reprise telle quelle.
    public let correlationID: CorrelationId

    /// Statut au moment du dépôt, pour que le support voie ce que l'utilisateur
    /// voyait — et non l'état au moment où il ouvre le dossier.
    public let observedStatus: PaymentStatus

    public let conversationID: String?

    /// Consentement explicite au partage des preuves avec le partenaire.
    ///
    /// Non optionnel et sans valeur par défaut : un consentement présumé n'en
    /// est pas un, et le partage à un tiers d'une preuve financière ne se
    /// déduit pas de l'ouverture d'un litige.
    public let sharingConsent: Bool

    public let evidenceReferences: [String]

    public init(
        reference: FinancialReference,
        reason: DisputeReason? = nil,
        description: String,
        correlationID: CorrelationId,
        observedStatus: PaymentStatus,
        conversationID: String? = nil,
        sharingConsent: Bool,
        evidenceReferences: [String] = [],
        category: String? = nil
    ) {
        self.reference = reference
        self.reason = reason
        self.category = category
        self.description = description
        self.correlationID = correlationID
        self.observedStatus = observedStatus
        self.conversationID = conversationID
        self.sharingConsent = sharingConsent
        self.evidenceReferences = evidenceReferences
    }
}

// MARK: - Préremplissage

public extension DisputeDraft {

    /// Construit un brouillon depuis une opération observée.
    ///
    /// Tout ce qui peut être repris l'est. L'utilisateur n'écrit que sa
    /// description et ne consent qu'une fois.
    static func prefilled(
        from reference: FinancialReference,
        observedStatus: PaymentStatus,
        reason: DisputeReason,
        conversationID: String? = nil
    ) -> DisputeDraft {
        DisputeDraft(
            reference: reference,
            reason: reason,
            description: "",
            // Reprise **telle quelle**, jamais régénérée : une corrélation neuve
            // couperait le lien avec les traces de l'opération contestée, qui
            // sont exactement ce que le support doit retrouver.
            correlationID: reference.correlationID,
            observedStatus: observedStatus,
            conversationID: conversationID,
            sharingConsent: false,
            evidenceReferences: []
        )
    }

    /// `true` si le brouillon peut être déposé.
    ///
    /// Le consentement est requis même quand aucune preuve n'est jointe : un
    /// litige transmet déjà l'opération et son contexte à un partenaire.
    var isSubmittable: Bool {
        sharingConsent && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ce que l'utilisateur n'aura pas à saisir. Pour l'afficher, et pour tester
    /// que le préremplissage fait réellement son travail.
    var prefilledFieldCount: Int {
        var count = 3 // référence, corrélation, statut observé
        if conversationID != nil { count += 1 }
        return count
    }
}
