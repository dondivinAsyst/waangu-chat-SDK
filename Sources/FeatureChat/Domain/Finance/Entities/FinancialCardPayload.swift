//
//  FinancialCardPayload.swift
//  FeatureChat
//
//  Ce qu'une carte financière affiche dans une conversation — tâche 4.1.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §5.4.

import Foundation
import WaanguCoreKit

/// Projection d'affichage d'un objet financier dans le fil.
///
/// **Miroir, jamais source.** Chaque champ vient du backend et n'est jamais
/// recalculé localement : un montant net dérivé côté client diverge du ledger dès
/// que la règle de frais change, et c'est le montant affiché que l'utilisateur
/// croit avoir payé.
///
/// Porte sa `FinancialReference`, donc sa révision : c'est ce qui permet au
/// magasin de refuser une mise à jour plus ancienne que celle déjà affichée.
public struct FinancialCardPayload: Equatable, Sendable, Codable {

    /// Identité et révision. Clé de toute la résolution de conflit.
    public let reference: FinancialReference

    /// Statut canonique. `unknown` est un état légitime, pas une erreur d'affichage.
    public let status: PaymentStatus

    /// Montant en unité majeure, tel que rendu par le backend.
    public let amount: Decimal
    public let currency: String

    /// Frais, si le backend les expose séparément.
    public let feeAmount: Decimal?

    /// Devise des frais, quand elle diffère de celle du montant.
    ///
    /// `PaymentEnvelope` porte `feeCurrency` séparément de `currency` — un
    /// paiement transfrontalier peut facturer ses frais dans une troisième
    /// devise. La charge la laissait tomber, et `totalAmount` additionnait alors
    /// deux devises sans le savoir.
    ///
    /// `nil` signifie « la même que `currency` », ce qui est le cas ordinaire.
    public let feeCurrency: String?

    /// Nom affichable de la contrepartie.
    ///
    /// Vient du backend et non de l'annuaire local : un nom de contact résolu
    /// localement peut désigner quelqu'un d'autre que le bénéficiaire réel, ce
    /// qui est exactement le levier d'une fraude au bénéficiaire.
    public let counterpartyName: String?

    /// Note libre attachée par l'émetteur.
    public let note: String?

    /// Instant de la dernière lecture serveur.
    ///
    /// Permet d'afficher « dernière mise à jour à HH:MM » hors ligne, plutôt que
    /// de présenter un état ancien comme s'il était courant.
    public let lastRefreshedAt: Date

    /// Verdict du garde sur la dernière confirmation reçue.
    ///
    /// Distinct de `status` : un objet peut porter `confirmed` sans que ce client
    /// ait pu le vérifier. La carte doit alors présenter l'incertitude.
    public let verification: FinancialCardVerification

    /// Actions que **le serveur** autorise sur cet objet (`allowedActions` de la
    /// carte, §7) — `CANCEL`, `REQUERY_FINANCE`, `VIEW_RECEIPT`… Optionnel pour
    /// rester décodable depuis une carte enregistrée avant ce champ.
    public let allowedActions: [String]?

    public init(
        reference: FinancialReference,
        status: PaymentStatus,
        amount: Decimal,
        currency: String,
        feeAmount: Decimal? = nil,
        feeCurrency: String? = nil,
        counterpartyName: String? = nil,
        note: String? = nil,
        lastRefreshedAt: Date = Date(),
        verification: FinancialCardVerification = .unverified,
        allowedActions: [String]? = nil
    ) {
        self.reference = reference
        self.status = status
        self.amount = amount
        self.currency = currency
        self.feeAmount = feeAmount
        self.feeCurrency = feeCurrency
        self.counterpartyName = counterpartyName
        self.note = note
        self.lastRefreshedAt = lastRefreshedAt
        self.verification = verification
        self.allowedActions = allowedActions
    }
}

// MARK: - Vérification

/// Ce que ce client a pu établir sur l'authenticité de l'objet.
public enum FinancialCardVerification: String, Codable, Sendable, Equatable {

    /// Signature backend vérifiée.
    case verified

    /// Non vérifiable — pas de clé, contrat backend non livré.
    /// La carte doit signaler l'incertitude, pas la masquer.
    case unverified

    /// Signature vérifiable et fausse. Ne jamais présenter le contenu comme réel.
    case rejected
}

// MARK: - Traitement d'affichage

/// Le seul vocabulaire dans lequel une carte financière a le droit de s'exprimer.
///
/// Existe pour une raison précise : tant que les vues lisaient `PaymentStatus`
/// directement, la règle « pas de succès sans vérification » était une propriété
/// que chaque vue devait penser à consulter — et qu'aucune ne consultait. Ici la
/// règle est appliquée une fois, à la construction, et le `status` brut n'est
/// plus accessible au rendu.
///
/// `settled` est le seul cas autorisant un vocabulaire, une icône et une teinte
/// de succès. Un objet `confirmed` non vérifié n'y accède pas : il sort en
/// `verifying`.
public enum FinancialCardPresentation: String, Sendable, Equatable, CaseIterable {

    /// Succès **vérifié**. Seul cas autorisant le vert.
    case settled

    /// Ce client ne sait pas conclure : statut `unknown`, ou succès non vérifié.
    case verifying

    case inFlight
    case atProvider
    case settling

    case failed
    case refused
    case cancelled
    case expired

    case refunded
    case partiallyRefunded
    case reversed
    case disputed

    case complianceReview

    /// Remboursement demandé, accordé ou en cours — **l'argent n'est pas revenu**.
    ///
    /// Distinct de `refunded` : annoncer un remboursement reçu alors qu'il peut
    /// encore échouer est la version « après-vente » du faux succès.
    case refundInProgress

    /// Rapprochement en cours côté backend.
    case reconciling

    /// Signature vérifiable et fausse. Le contenu n'est pas présenté comme réel.
    case repudiated

    /// `true` si ce traitement a le droit d'annoncer une opération aboutie.
    ///
    /// Un seul point de vérité pour les vues, les tests et toute future carte.
    public var announcesSuccess: Bool { self == .settled }
}

// MARK: - Présentation

public extension FinancialCardPayload {

    /// `true` si la carte peut présenter l'opération comme aboutie.
    ///
    /// Exige **les deux** : un statut final de succès **et** une vérification
    /// réussie. Un objet `confirmed` non vérifié s'affiche comme en cours de
    /// vérification — c'est la différence entre afficher la vérité et afficher
    /// ce que l'on nous a dit.
    var canPresentAsSettled: Bool {
        (status == .confirmed || status == .completed) && verification == .verified
    }

    /// `true` si seule une interrogation du backend peut lever l'ambiguïté.
    ///
    /// INTEGRATION_CHAT_FINANCE.md : on relit la carte après un MQTT
    /// `OBJECT_CHANGED` (§7), et on requête ce qui est **en doute après un
    /// execute** (Phase 9) — `SUBMITTED` / `PROCESSING` ne deviennent pas
    /// `COMPLETED` tant que Finance n'a pas confirmé (§3.3). Rien ne demande de
    /// sonder un objet qui attend **une personne** : une demande que le payeur
    /// n'a pas encore réglée, un devis non confirmé, une décision de
    /// conformité. Les sonder relisait chaque minute des objets qui ne
    /// pouvaient pas changer sans un `OBJECT_CHANGED`.
    var needsReconciliation: Bool {
        switch status {
        case .unknown, .inDoubt:
            // En doute (IN_DOUBT, timeout après envoi).
            return true
        case .confirmed, .completed:
            // Succès annoncé, pas encore vérifié : seul le backend tranche.
            return verification == .unverified
        case .queued, .processing, .authorized, .pendingProvider,
             .pendingSettlement, .pendingReconciliation, .reconciling, .refundProcessing:
            // Parti après un execute, Finance n'a pas encore conclu.
            return true
        default:
            // Attend une personne, ou déjà final.
            return false
        }
    }

    /// Même objet, lu à nouveau à `date` sans rien de changé.
    func checked(at date: Date) -> FinancialCardPayload {
        FinancialCardPayload(reference: reference, status: status, amount: amount,
                             currency: currency, feeAmount: feeAmount, feeCurrency: feeCurrency,
                             counterpartyName: counterpartyName, note: note,
                             lastRefreshedAt: date, verification: verification)
    }

    /// `true` si le contenu ne doit pas être présenté comme réel.
    var isRepudiated: Bool { verification == .rejected }

    /// Traitement d'affichage de cette carte.
    ///
    /// Passe obligatoire : c'est ici, et nulle part ailleurs, que le statut
    /// backend et le verdict de vérification se combinent en ce que la carte a
    /// le droit de montrer.
    var presentation: FinancialCardPresentation {
        guard !isRepudiated else { return .repudiated }

        switch status {
        case .confirmed, .completed:
            // La porte du Bloc 1. Un succès non vérifié n'est pas un succès
            // affichable — c'est une vérification en cours.
            return canPresentAsSettled ? .settled : .verifying

        case .unknown, .inDoubt:
            return .verifying

        case .queued, .syncing, .pending, .processing, .authorized:
            return .inFlight

        case .pendingProvider:
            return .atProvider

        case .pendingSettlement:
            return .settling

        case .failed:              return .failed
        case .restricted, .denied: return .refused
        case .cancelled:           return .cancelled
        case .expired:             return .expired
        case .refunded:            return .refunded
        case .partiallyRefunded:   return .partiallyRefunded
        case .reversed:            return .reversed
        case .disputed:            return .disputed

        case .complianceHold, .amlReview:
            return .complianceReview

        case .refundRequested, .refundApproved, .refundProcessing:
            return .refundInProgress

        case .compliancePending, .authorizationRequired:
            return .complianceReview

        case .pendingReconciliation:
            // Débité mais non rapproché : c'est une réconciliation, pas un
            // succès. Le classer ailleurs rouvrirait le faux succès par le côté.
            return .reconciling

        case .reconciling:
            return .reconciling
        }
    }

    /// Montant total supporté par l'émetteur, frais compris.
    /// Montant total supporté par l'émetteur, frais compris.
    ///
    /// `nil` quand les frais sont libellés dans une autre devise que le montant :
    /// il n'existe alors pas de total, seulement deux sommes distinctes. Rendre
    /// une addition dans ce cas afficherait un nombre qui ne correspond à aucune
    /// somme réelle — et la conversion appartient au backend, pas à cette carte.
    ///
    /// Le type de retour est volontairement optionnel plutôt que de retomber sur
    /// `amount` seul : un total silencieusement amputé de ses frais est un
    /// mensonge plus discret, donc pire, qu'une absence de total.
    var totalAmount: Decimal? {
        guard let feeAmount else { return amount }
        guard feeCurrency == nil || feeCurrency == currency else { return nil }
        return amount + feeAmount
    }

    /// `true` si les frais s'expriment dans une autre devise que le montant.
    /// La carte doit alors les présenter séparément, jamais additionnés.
    var hasForeignCurrencyFee: Bool {
        guard feeAmount != nil, let feeCurrency else { return false }
        return feeCurrency != currency
    }

    /// Applique une mise à jour si et seulement si elle est plus récente.
    ///
    /// - Returns: la charge à conserver. Retourne `self` inchangé quand
    ///   l'entrante est périmée — jamais `nil`, pour qu'un site d'appel
    ///   distrait ne puisse pas effacer l'état courant.
    func merging(_ incoming: FinancialCardPayload) -> FinancialCardPayload {
        incoming.reference.supersedes(reference) ? incoming : self
    }
}
