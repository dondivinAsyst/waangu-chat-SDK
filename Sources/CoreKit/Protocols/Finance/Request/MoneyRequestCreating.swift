//
//  MoneyRequestCreating.swift
//  CoreKit
//
//  Émission d'une demande d'argent — Bloc 3, chapitre 17.
//
//  **BACKEND CONTRACT REQUIRED** — `POST /v1/requests`, `/remind`, `/cancel`.
//

import Foundation

/// Crée et gère les demandes d'argent.
///
/// Une demande d'argent est un message que n'importe qui peut adresser à
/// n'importe qui, dans une application qui porte déjà l'audience. C'est ce qui
/// rend `MoneyRequestPolicy` inséparable de ce contrat : sans bornes de relance
/// et sans blocage, la fonctionnalité **est** un canal de harcèlement.
public protocol MoneyRequestCreating: Sendable {

    /// Politique applicable à l'émetteur pour ce destinataire.
    ///
    /// À consulter **avant** d'ouvrir le formulaire, pas au moment d'envoyer :
    /// laisser composer une demande pour la refuser ensuite est une friction
    /// gratuite, et laisse croire que le refus est technique.
    func policy(towards recipientID: String) async -> Result<MoneyRequestPolicy, FinanceError>

    /// Crée la demande.
    ///
    /// - Parameter idempotency: fournie par l'appelant, jamais fabriquée ici —
    ///   un double tap doit produire une demande, pas deux.
    func createRequest(
        _ draft: MoneyRequestDraft,
        idempotency: IdempotencyContext
    ) async -> Result<FinancialReference, FinanceError>

    /// Relance une demande existante. Le backend applique le throttling ; le
    /// client l'applique aussi, pour ne pas proposer un geste voué au refus.
    func remind(_ reference: FinancialReference,
                idempotency: IdempotencyContext) async -> Result<Void, FinanceError>

    /// Révoque la demande **et tout lien ou QR** qui en dérive.
    func revoke(_ reference: FinancialReference,
                idempotency: IdempotencyContext) async -> Result<Void, FinanceError>
}

// MARK: - Brouillon

/// Ce que l'utilisateur a composé. Rien n'y est définitif.
public struct MoneyRequestDraft: Sendable, Hashable, Codable {

    /// Identifiant **résolu** par le backend. Jamais un numéro de téléphone.
    public let recipientID: String

    /// Montant souhaité. Le backend reste l'arbitre des bornes.
    /// `nil` ⇒ montant libre : le payeur choisira.
    public let amount: Decimal?

    public let currency: String

    /// Conversation d'origine. Ne confère aucun droit — l'autorisation ne
    /// dépend pas de la conversation.
    public let conversationID: String?

    public let note: String?

    /// Échéance souhaitée. Le backend peut la borner ou la refuser.
    public let expiresAt: Date?

    /// Utilisateur Chat de l'interlocuteur, quand la demande part d'une
    /// conversation directe.
    ///
    /// Le contrat nomme les parties par **userId Chat** (§4). Il se lit
    /// d'abord dans la résolution du bénéficiaire ; celle-ci peut ne pas le
    /// rendre. Ce n'est alors qu'un repli, et il ne remplace jamais la
    /// résolution : sans bénéficiaire résolu, aucune demande ne part. Le
    /// serveur reste seul juge de la partie.
    public let recipientChatUserID: String?

    public init(
        recipientID: String,
        amount: Decimal?,
        currency: String,
        conversationID: String? = nil,
        note: String? = nil,
        expiresAt: Date? = nil,
        recipientChatUserID: String? = nil
    ) {
        self.recipientID = recipientID
        self.amount = amount
        self.currency = currency
        self.conversationID = conversationID
        self.note = note
        self.expiresAt = expiresAt
        self.recipientChatUserID = recipientChatUserID
    }
}

// MARK: - Politique anti-abus

/// Bornes que l'émetteur ne peut pas franchir vers ce destinataire.
///
/// **BACKEND SOURCE OF TRUTH.** Le client ne les invente pas : il les reçoit et
/// les applique. Codées en dur, elles seraient contournables par une
/// réinstallation, et non ajustables face à un abus constaté.
public struct MoneyRequestPolicy: Codable, Sendable, Hashable {

    public let maxRemindersPerRequest: Int
    public let minIntervalBetweenReminders: TimeInterval
    public let maxOpenRequestsPerRecipient: Int

    /// `false` ⇒ demander à quelqu'un hors de ses contacts est refusé.
    public let allowsRequestToNonContacts: Bool

    /// Le destinataire a bloqué l'émetteur. **Décidé backend** : le client ne
    /// connaît pas les blocages qu'il subit, seulement ceux qu'il pose.
    public let recipientHasBlockedSender: Bool

    public init(
        maxRemindersPerRequest: Int,
        minIntervalBetweenReminders: TimeInterval,
        maxOpenRequestsPerRecipient: Int,
        allowsRequestToNonContacts: Bool,
        recipientHasBlockedSender: Bool
    ) {
        self.maxRemindersPerRequest = maxRemindersPerRequest
        self.minIntervalBetweenReminders = minIntervalBetweenReminders
        self.maxOpenRequestsPerRecipient = maxOpenRequestsPerRecipient
        self.allowsRequestToNonContacts = allowsRequestToNonContacts
        self.recipientHasBlockedSender = recipientHasBlockedSender
    }

    /// Politique la plus restrictive. Repli en toute circonstance douteuse.
    ///
    /// Zéro relance, zéro demande ouverte, pas de non-contacts. Un abus se
    /// répare, une demande jamais partie ne fait de mal à personne.
    public static let closed = MoneyRequestPolicy(
        maxRemindersPerRequest: 0,
        minIntervalBetweenReminders: .greatestFiniteMagnitude,
        maxOpenRequestsPerRecipient: 0,
        allowsRequestToNonContacts: false,
        recipientHasBlockedSender: false
    )
}

// MARK: - Verdict

public enum MoneyRequestVerdict: Sendable, Equatable {
    case allowed
    /// Refusé, avec une clé de message expliquant pourquoi.
    case refused(reasonKey: String)
}

public extension MoneyRequestPolicy {

    /// Une nouvelle demande est-elle permise vers ce destinataire ?
    ///
    /// - Parameter openRequests: demandes déjà ouvertes vers lui.
    /// - Parameter isContact: le destinataire est-il dans les contacts.
    func verdictForNewRequest(
        openRequests: Int,
        isContact: Bool
    ) -> MoneyRequestVerdict {
        // Le blocage l'emporte sur tout le reste : c'est un refus de la
        // personne, pas une borne de volume.
        if recipientHasBlockedSender {
            return .refused(reasonKey: "finance.request.refused.blocked")
        }
        if !isContact && !allowsRequestToNonContacts {
            return .refused(reasonKey: "finance.request.refused.not_a_contact")
        }
        if openRequests >= maxOpenRequestsPerRecipient {
            return .refused(reasonKey: "finance.request.refused.too_many_open")
        }
        return .allowed
    }

    /// Une relance est-elle permise maintenant ?
    ///
    /// - Parameter remindersSent: relances déjà envoyées sur cette demande.
    /// - Parameter lastReminderAt: instant de la dernière, `nil` si aucune.
    func verdictForReminder(
        remindersSent: Int,
        lastReminderAt: Date?,
        now: Date = Date()
    ) -> MoneyRequestVerdict {
        if recipientHasBlockedSender {
            return .refused(reasonKey: "finance.request.refused.blocked")
        }
        if remindersSent >= maxRemindersPerRequest {
            return .refused(reasonKey: "finance.request.refused.reminder_limit")
        }
        if let lastReminderAt,
           now.timeIntervalSince(lastReminderAt) < minIntervalBetweenReminders {
            return .refused(reasonKey: "finance.request.refused.reminder_too_soon")
        }
        return .allowed
    }
}

// MARK: - Répondre à une demande — Chat Core §4

/// Ce qu'une demande d'argent dit **à celui qui la regarde**.
///
/// Lu sur `GET /request-money/{requestRef}` (`RequestView`). Les actions
/// possibles sont celles que le serveur liste dans `nextSafeActions` : le
/// client n'en déduit aucune du statut. Une demande payée, expirée ou annulée
/// ne liste plus `PAY`, et le bouton disparaît sans règle locale.
public struct MoneyRequestOverlay: Sendable, Hashable {

    public enum AmountMode: String, Sendable, Hashable {
        /// Montant fixé par le demandeur.
        case fixed = "FIXED"
        /// Montant choisi par le payeur.
        case free = "FREE"
    }

    public let reference: FinancialReference
    /// `OPEN` ⇒ `.pending` · `EXPIRED` · `CANCELLED` · `COMPLETED`.
    public let status: PaymentStatus
    /// Celui qui regarde est l'auteur de la demande.
    public let isRequester: Bool
    public let amountMode: AmountMode
    public let currency: String
    /// Total demandé — tel que le serveur le rend.
    public let requestedTotal: Decimal?
    /// Ce qui reste à payer **pour celui qui regarde**, s'il est partie
    /// (`parties[].remainingMinor`). `nil` pour le demandeur.
    public let myRemaining: Decimal?
    /// Actions listées par le serveur (`nextSafeActions`), en majuscules.
    public let nextSafeActions: Set<String>
    /// Parties qui n'ont pas encore tout payé — ce que « Relancer » vise.
    public let pendingPartyUserIDs: [String]
    /// Statut de **ma** part (`parties[].status`), en majuscules — `nil` pour
    /// le demandeur. Après un paiement, la demande reste souvent `OPEN` : c'est
    /// ma part qui passe à `PAYMENT_SUBMITTED`, puis `PAID`.
    public let myPartyStatus: String?
    /// Conversation de la demande — celle où la payer (`/request-money/pay`).
    public let conversationID: String?

    /// Nature de l'objet (`kind`) : `REQUEST_MONEY`, `SPLIT_BILL`, …
    ///
    /// Les deux se lisent par la **même** vue et la même carte — un partage est
    /// une demande à plusieurs parts nommées — mais ne se paient pas par la
    /// même route. Sans cette nature, payer sa part d'un partage appelait
    /// `/request-money/pay`.
    public let kind: String?

    public init(reference: FinancialReference, status: PaymentStatus, isRequester: Bool,
                amountMode: AmountMode, currency: String, requestedTotal: Decimal?,
                myRemaining: Decimal?, nextSafeActions: Set<String>, pendingPartyUserIDs: [String],
                myPartyStatus: String? = nil, conversationID: String? = nil,
                kind: String? = nil) {
        self.reference = reference
        self.status = status
        self.isRequester = isRequester
        self.amountMode = amountMode
        self.currency = currency
        self.requestedTotal = requestedTotal
        self.myRemaining = myRemaining
        self.nextSafeActions = nextSafeActions
        self.pendingPartyUserIDs = pendingPartyUserIDs
        self.myPartyStatus = myPartyStatus?.uppercased()
        self.conversationID = conversationID
        self.kind = kind?.uppercased()
    }

    /// Un partage d'addition, et non une demande ordinaire.
    public var isSplitBill: Bool { kind == "SPLIT_BILL" }

    /// Ce que ma part est devenue, une fois que j'ai agi.
    public enum MyShare: Sendable, Equatable {
        case paymentSent
        case paid
        case declined
    }

    /// `nil` tant que ma part attend (`PENDING`, `PARTIALLY_PAID`…).
    public var myShare: MyShare? {
        switch myPartyStatus {
        case "PAYMENT_SUBMITTED", "PROCESSING", "PENDING_SETTLEMENT": return .paymentSent
        case "PAID", "COMPLETED", "SETTLED":                          return .paid
        case "DECLINED", "REJECTED":                                  return .declined
        default:                                                      return nil
        }
    }

    /// Payer n'a de sens que pour une partie, et seulement si le serveur le propose.
    ///
    /// Le serveur écrit `PAY_REQUEST` / `DECLINE_REQUEST` au payeur ; le
    /// contrat montre `PAY` / `DECLINE`. Les deux orthographes sont lues.
    ///
    /// Une part déjà réglée, envoyée ou refusée ne se repaie pas, même si une
    /// réponse périmée liste encore `PAY_REQUEST` : un double paiement coûte
    /// plus cher qu'un bouton absent une seconde de trop.
    public var canPay: Bool {
        !isRequester && myShare == nil
            && !nextSafeActions.isDisjoint(with: ["PAY_REQUEST", "PAY", "PAY_SHARE"])
    }
    public var canDecline: Bool {
        !isRequester && myShare == nil && !nextSafeActions.isDisjoint(with: ["DECLINE_REQUEST", "DECLINE"])
    }
    /// Relancer : quand le serveur le propose au demandeur (`REMIND`), et
    /// qu'il reste quelqu'un à relancer.
    public var canRemind: Bool {
        isRequester && nextSafeActions.contains("REMIND") && !pendingPartyUserIDs.isEmpty
    }
    /// Le serveur dit d'attendre (`WAIT`) — ce n'est pas un geste, c'est un
    /// état : la demande attend un paiement. Affiché à côté des gestes proposés
    /// (relancer, lien, annuler), pas à leur place.
    ///
    /// Pas quand ma part est déjà réglée ou envoyée : la ligne de part le dit
    /// déjà, et « en attente » à côté de « Paiement envoyé » se contredirait.
    public var isWaiting: Bool {
        nextSafeActions.contains("WAIT") && myShare == nil
    }
    /// Émettre un lien de paiement — `ISSUE_PAYMENT_LINK` proposé au demandeur.
    public var canIssueLink: Bool {
        isRequester && nextSafeActions.contains("ISSUE_PAYMENT_LINK")
    }
    /// Annuler sa propre demande — `CANCEL_INTENT` (ou `CANCEL`) proposé au demandeur.
    public var canCancel: Bool {
        isRequester && !nextSafeActions.isDisjoint(with: ["CANCEL_INTENT", "CANCEL"])
    }
}

/// Répondre à une demande reçue, ou relancer une demande envoyée.
///
/// **Payer n'est pas un débit** (§4) : `pay` rend un devis — le même que le
/// prepare de Send Money — qui se confirme ensuite par le parcours d'envoi,
/// avec confirmation humaine explicite. Aucune méthode ici ne déplace d'argent.
public protocol MoneyRequestResponding: Sendable {
    func overlay(for reference: FinancialReference) async -> Result<MoneyRequestOverlay, FinanceError>
    /// `POST /request-money/pay`. `amount` seulement pour une demande `FREE`.
    func pay(_ reference: FinancialReference, conversationID: String?,
             amount: Decimal?, currency: String?) async -> Result<TransferQuote, FinanceError>
    /// `POST /request-money/decline`.
    func decline(_ reference: FinancialReference, conversationID: String?) async -> Result<Void, FinanceError>
    /// `POST /request-money/remind` — la partie est nommée, pas devinée.
    func remind(_ reference: FinancialReference, partyUserID: String) async -> Result<Void, FinanceError>
    /// `POST /intent/cancel` — Phase 10. L'annulation peut n'être que demandée.
    func cancel(_ reference: FinancialReference,
                conversationID: String?) async -> Result<MoneyRequestCancelOutcome, FinanceError>
    /// Oublie toute lecture gardée de cette demande — après une action faite
    /// ailleurs que par ce répondeur (l'execute d'un paiement).
    func forget(_ reference: FinancialReference) async
    /// `POST /request-money/payment-link` — un lien vers **cette** demande. Jamais exécutable.
    func issueLink(for reference: FinancialReference,
                   conversationID: String?) async -> Result<MoneyRequestLink, FinanceError>
    /// `POST /request-money/payment-link/inspect` — le contexte seulement : la demande que le
    /// lien désigne, à payer ensuite par `pay` (quote → confirmation). `CF_036`
    /// si le lien est invalide.
    func inspectLink(token: String, nonce: String) async -> Result<MoneyRequestOverlay, FinanceError>
}

public extension MoneyRequestResponding {
    /// Oublie toute lecture gardée de cette demande : la suivante part au
    /// serveur. Sans cache, rien à faire.
    func forget(_ reference: FinancialReference) async {}

    func issueLink(for reference: FinancialReference,
                   conversationID: String?) async -> Result<MoneyRequestLink, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func inspectLink(token: String, nonce: String) async -> Result<MoneyRequestOverlay, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

/// Lien de paiement d'une demande — `PaymentLink`, INTEGRATION_CHAT_FINANCE.md
/// Phase 4. **Jamais exécutable** : il ne paie rien, il désigne une demande
/// qu'on paie ensuite par le parcours normal.
public struct MoneyRequestLink: Sendable, Equatable {
    public let token: String
    public let nonce: String
    public let requestRef: String
    public let conversationID: String?
    public let expiresAt: Date?
    /// Toujours `false` selon le contrat. Lu, jamais utilisé pour payer.
    public let executable: Bool
    public let consumedAt: Date?

    public init(token: String, nonce: String, requestRef: String, conversationID: String?,
                expiresAt: Date?, executable: Bool, consumedAt: Date?) {
        self.token = token
        self.nonce = nonce
        self.requestRef = requestRef
        self.conversationID = conversationID
        self.expiresAt = expiresAt
        self.executable = executable
        self.consumedAt = consumedAt
    }

    /// Consommé ou expiré : ne se partage plus.
    public func isUsable(at now: Date = Date()) -> Bool {
        guard consumedAt == nil else { return false }
        guard let expiresAt else { return true }
        return expiresAt > now
    }
}

/// Issue d'une annulation. `CF_046` (202) : « cancel demandé, pas final » —
/// la carte ne passe à « annulée » que lorsque le serveur le dit.
public enum MoneyRequestCancelOutcome: Sendable, Equatable {
    case cancelled
    case requested
}
