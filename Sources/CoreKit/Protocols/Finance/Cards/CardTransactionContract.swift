//
//  CardTransactionContract.swift
//  CoreKit
//
//  Transactions cartes, 3DS et contestations — Bloc 6, chapitre 49.
//
//  **BACKEND CONTRACT REQUIRED** — autorisation, capture, règlement,
//  annulation, remboursement, 3DS, litige, rétrofacturation.
//

import Foundation

/// Historique et suites d'une transaction carte.
///
/// Le chapitre 49 l'écrit sans détour : « Ne jamais réduire les cartes à
/// success / failed. » Une carte passe par des étapes **qui ne sont pas
/// interchangeables** :
///
///     AUTHORIZED ≠ CAPTURED ≠ SETTLED
///
/// Une autorisation réserve des fonds sans les déplacer. Une capture les
/// déplace. Un règlement les rend définitifs. Confondre les trois fait annoncer
/// « payé » sur une réservation d'essence de 150 € dont 40 € seront capturés.
public protocol CardTransactionProviding: Sendable {

    func transactions(cardID: String, cursor: String?) async -> Result<[CardTransaction], FinanceError>
    func transaction(id: String) async -> Result<CardTransaction, FinanceError>

    /// Signale une transaction non reconnue.
    ///
    /// Distinct d'un litige commercial : ici l'utilisateur affirme ne pas être
    /// à l'origine de l'opération. Les confondre ferait traiter une fraude
    /// comme un désaccord avec un marchand.
    func reportUnrecognized(
        transactionID: String,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<CardDispute, FinanceError>

    /// Ouvre un litige sur une transaction carte.
    func openDispute(
        _ request: CardDisputeRequest,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<CardDispute, FinanceError>

    func dispute(id: String) async -> Result<CardDispute, FinanceError>
    func disputes(cursor: String?) async -> Result<[CardDispute], FinanceError>
}

// MARK: - La transaction

public struct CardTransaction: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let cardID: String
    public let reference: FinancialReference

    public let state: CardTransactionState

    /// Montant **autorisé** — réservé, pas forcément débité.
    public let authorizedAmount: Money

    /// Montant **capturé**. `nil` tant que rien n'est capturé.
    ///
    /// Peut différer de l'autorisation : la station-service réserve large et
    /// capture le plein réel. Afficher l'autorisation comme un débit ferait
    /// croire à un prélèvement qui n'aura jamais lieu.
    public let capturedAmount: Money?

    /// Montant **réglé**, définitif.
    public let settledAmount: Money?

    /// Montant remboursé, cumulé.
    public let refundedAmount: Money?

    public let merchantNameKey: String
    public let merchantCategoryCode: String?

    /// Devise d'origine, quand elle diffère de celle de la carte.
    public let originalCurrency: String?
    public let originalAmount: Decimal?

    public let occurredAt: Date
    public let updatedAt: Date

    /// Session 3DS, quand la transaction en a demandé une.
    public let threeDSecure: ThreeDSecureOutcome?

    /// Motif de refus, en clé. `nil` si la transaction n'a pas été refusée.
    public let declineReasonKey: String?

    /// Retrait en distributeur.
    public let isATM: Bool

    public init(
        id: String, cardID: String, reference: FinancialReference,
        state: CardTransactionState, authorizedAmount: Money,
        capturedAmount: Money? = nil, settledAmount: Money? = nil,
        refundedAmount: Money? = nil, merchantNameKey: String,
        merchantCategoryCode: String? = nil, originalCurrency: String? = nil,
        originalAmount: Decimal? = nil, occurredAt: Date, updatedAt: Date,
        threeDSecure: ThreeDSecureOutcome? = nil, declineReasonKey: String? = nil,
        isATM: Bool = false
    ) {
        self.id = id
        self.cardID = cardID
        self.reference = reference
        self.state = state
        self.authorizedAmount = authorizedAmount
        self.capturedAmount = capturedAmount
        self.settledAmount = settledAmount
        self.refundedAmount = refundedAmount
        self.merchantNameKey = merchantNameKey
        self.merchantCategoryCode = merchantCategoryCode
        self.originalCurrency = originalCurrency
        self.originalAmount = originalAmount
        self.occurredAt = occurredAt
        self.updatedAt = updatedAt
        self.threeDSecure = threeDSecure
        self.declineReasonKey = declineReasonKey
        self.isATM = isATM
    }

    /// Le montant à **afficher**, et ce qu'il représente.
    ///
    /// L'ordre n'est pas cosmétique : le plus définitif l'emporte. Montrer
    /// l'autorisation quand la capture est connue afficherait un montant que le
    /// relevé bancaire contredira.
    public var displayedAmount: (amount: Money, authority: CardAmountAuthority) {
        if let settledAmount { return (settledAmount, .settled) }
        if let capturedAmount { return (capturedAmount, .captured) }
        return (authorizedAmount, .authorized)
    }

    /// Contestable. Une autorisation seule ne l'est pas : rien n'a encore été
    /// débité, et l'annuler relève du marchand, pas du réseau.
    public func isDisputable(at now: Date = Date()) -> Bool {
        state.hasMovedMoney
    }
}

/// D'où vient le montant affiché.
public enum CardAmountAuthority: String, Sendable, Equatable {
    /// Réservé. **Pas encore débité.**
    case authorized
    /// Débité. Encore modifiable jusqu'au règlement.
    case captured
    /// Définitif.
    case settled
}

// MARK: - Machine d'état (§14)

/// États d'une transaction carte.
///
/// Trois temps distincts plus leurs branches. Aucun ne se déduit d'un autre :
/// c'est le réseau qui les pose, et le client les affiche.
public enum CardTransactionState: String, Codable, Sendable, CaseIterable {

    /// Autorisation demandée, réponse attendue.
    case pending          = "PENDING"

    /// Fonds réservés. **Pas débités.**
    case authorized       = "AUTHORIZED"

    /// Autorisation refusée par l'émetteur ou le réseau.
    case declined         = "DECLINED"

    /// Fonds déplacés vers le marchand.
    case captured         = "CAPTURED"

    /// Réglé. Définitif.
    case settled          = "SETTLED"

    /// Autorisation annulée avant capture — le cas courant d'une réservation
    /// qui expire. **Aucun argent n'a bougé.**
    case reversed         = "REVERSED"

    /// Remboursement total ou partiel après capture.
    case refunded         = "REFUNDED"
    case partiallyRefunded = "PARTIALLY_REFUNDED"

    /// Contestée : un litige ou une rétrofacturation est ouvert.
    case disputed         = "DISPUTED"

    /// Fonds repris par le réseau au profit du porteur.
    case chargedBack      = "CHARGED_BACK"

    /// L'autorisation a expiré sans capture.
    case expired          = "EXPIRED"

    /// État connu du backend mais pas de ce client.
    ///
    /// **Ni succès, ni échec.** Le §19 l'exige : un état inconnu ne déclenche
    /// jamais un nouveau paiement et ne s'affiche jamais comme abouti.
    case unknown          = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardTransactionState(rawValue: raw) ?? .unknown
    }

    /// De l'argent a effectivement quitté le compte.
    ///
    /// `authorized` en est exclu : c'est toute la distinction du chapitre 49.
    public var hasMovedMoney: Bool {
        switch self {
        case .captured, .settled, .refunded, .partiallyRefunded,
             .disputed, .chargedBack:
            return true
        case .pending, .authorized, .declined, .reversed, .expired, .unknown:
            return false
        }
    }

    /// Plus aucune évolution attendue.
    public var isTerminal: Bool {
        switch self {
        case .settled, .declined, .reversed, .expired, .chargedBack: return true
        default: return false
        }
    }

    /// Doit être requêté à nouveau plutôt qu'affiché comme définitif (§19).
    public var requiresRequery: Bool {
        self == .pending || self == .unknown
    }
}

/// Transitions autorisées entre états de transaction carte.
///
/// Sépare « est-ce plus récent ? » de « est-ce possible ? ». Une capture qui
/// arriverait après un règlement est un désordre de messages ; la traiter comme
/// une régression légitime ferait reculer l'affichage.
public enum CardTransactionStateMachine {

    /// Ce qu'un état peut devenir.
    public static func allowedTransitions(from state: CardTransactionState) -> Set<CardTransactionState> {
        switch state {
        case .pending:
            return [.authorized, .declined, .expired, .unknown]
        case .authorized:
            // Une autorisation ne va **jamais** directement à `settled` :
            // le règlement suppose une capture.
            return [.captured, .reversed, .expired, .disputed, .unknown]
        case .captured:
            return [.settled, .refunded, .partiallyRefunded, .disputed, .unknown]
        case .settled:
            return [.refunded, .partiallyRefunded, .disputed, .unknown]
        case .partiallyRefunded:
            return [.refunded, .disputed, .settled, .unknown]
        case .refunded:
            return [.disputed, .unknown]
        case .disputed:
            return [.chargedBack, .settled, .refunded, .unknown]
        case .declined, .reversed, .expired, .chargedBack:
            // États terminaux : rien n'en sort.
            return []
        case .unknown:
            // Un état inconnu peut se résoudre vers n'importe quoi de connu :
            // c'est le sens même d'une requête de clarification.
            return Set(CardTransactionState.allCases).subtracting([.unknown])
        }
    }

    public static func isAllowed(from current: CardTransactionState,
                                 to next: CardTransactionState) -> Bool {
        if current == next { return true }
        return allowedTransitions(from: current).contains(next)
    }

    /// Verdict motivé, pour la journalisation.
    public static func verdict(from current: CardTransactionState,
                               to next: CardTransactionState) -> CardTransitionVerdict {
        if current == next { return .allowed }
        guard allowedTransitions(from: current).contains(next) else {
            return .forbidden(reason: "\(current.rawValue) → \(next.rawValue)")
        }
        return .allowed
    }
}

public enum CardTransitionVerdict: Sendable, Equatable {
    case allowed
    case forbidden(reason: String)
}

// MARK: - 3D Secure

/// Résultat d'une authentification 3DS.
public struct ThreeDSecureOutcome: Codable, Sendable, Hashable {
    public let sessionID: String
    public let flow: ThreeDSecureFlow
    public let result: ThreeDSecureResult
    public let occurredAt: Date

    public init(sessionID: String, flow: ThreeDSecureFlow,
                result: ThreeDSecureResult, occurredAt: Date) {
        self.sessionID = sessionID
        self.flow = flow
        self.result = result
        self.occurredAt = occurredAt
    }
}

public enum ThreeDSecureFlow: String, Codable, Sendable, CaseIterable {
    /// Authentifié sans geste de l'utilisateur.
    case frictionless = "FRICTIONLESS"
    /// L'utilisateur a dû répondre à un défi.
    case challenge    = "CHALLENGE"
    case unknown      = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ThreeDSecureFlow(rawValue: raw) ?? .unknown
    }
}

public enum ThreeDSecureResult: String, Codable, Sendable, CaseIterable {
    case authenticated = "AUTHENTICATED"
    case attempted     = "ATTEMPTED"
    case failed        = "FAILED"
    case rejected      = "REJECTED"
    case unavailable   = "UNAVAILABLE"
    case unknown       = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ThreeDSecureResult(rawValue: raw) ?? .unknown
    }

    /// `attempted` **n'est pas** `authenticated` : la tentative transfère la
    /// responsabilité sans prouver l'identité. Les confondre à l'affichage
    /// laisserait croire à une authentification qui n'a pas eu lieu.
    public var isAuthenticated: Bool { self == .authenticated }
}

// MARK: - Litiges et rétrofacturation

public struct CardDisputeRequest: Sendable, Hashable, Codable {
    public let transactionID: String
    public let kind: CardDisputeKind
    public let reasonKey: String
    public let commentText: String?
    /// Pièces déjà téléversées — identifiants, jamais des données.
    public let evidenceIDs: [String]
    /// Montant contesté. `nil` ⇒ la totalité.
    public let disputedAmount: Money?

    public init(transactionID: String, kind: CardDisputeKind, reasonKey: String,
                commentText: String? = nil, evidenceIDs: [String] = [],
                disputedAmount: Money? = nil) {
        self.transactionID = transactionID
        self.kind = kind
        self.reasonKey = reasonKey
        self.commentText = commentText
        self.evidenceIDs = evidenceIDs
        self.disputedAmount = disputedAmount
    }

    public var isSubmittable: Bool { !reasonKey.isEmpty }
}

public enum CardDisputeKind: String, Codable, Sendable, CaseIterable {
    /// Le porteur n'est pas à l'origine de l'opération.
    case unrecognized     = "UNRECOGNIZED"
    /// Bien ou service non reçu.
    case serviceNotReceived = "SERVICE_NOT_RECEIVED"
    /// Non conforme à la description.
    case notAsDescribed   = "NOT_AS_DESCRIBED"
    /// Débité deux fois.
    case duplicate        = "DUPLICATE"
    /// Montant incorrect.
    case incorrectAmount  = "INCORRECT_AMOUNT"
    /// Remboursement promis et jamais reçu.
    case refundNotReceived = "REFUND_NOT_RECEIVED"
}

public struct CardDispute: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let transactionID: String
    public let kind: CardDisputeKind
    public let state: CardDisputeState
    public let openedAt: Date
    public let updatedAt: Date
    /// Rétrofacturation, quand le réseau en ouvre une.
    public let chargeback: Chargeback?
    /// Ce que le réseau attend encore du porteur.
    public let requiredEvidenceKeys: [String]

    public init(id: String, transactionID: String, kind: CardDisputeKind,
                state: CardDisputeState, openedAt: Date, updatedAt: Date,
                chargeback: Chargeback? = nil, requiredEvidenceKeys: [String] = []) {
        self.id = id
        self.transactionID = transactionID
        self.kind = kind
        self.state = state
        self.openedAt = openedAt
        self.updatedAt = updatedAt
        self.chargeback = chargeback
        self.requiredEvidenceKeys = requiredEvidenceKeys
    }
}

public enum CardDisputeState: String, Codable, Sendable, CaseIterable {
    case opened            = "OPENED"
    case evidenceRequested = "EVIDENCE_REQUESTED"
    case underReview       = "UNDER_REVIEW"
    case accepted          = "ACCEPTED"
    case rejected          = "REJECTED"
    case withdrawn         = "WITHDRAWN"
    case unknown           = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardDisputeState(rawValue: raw) ?? .unknown
    }
}

/// Reprise de fonds par le réseau.
///
/// Distincte du litige : le litige est la demande, la rétrofacturation est
/// l'opération financière que le réseau exécute — ou non.
public struct Chargeback: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let state: ChargebackState
    public let amount: Money
    public let openedAt: Date
    /// Échéance de représentation par le marchand.
    public let respondBy: Date?

    public init(id: String, state: ChargebackState, amount: Money,
                openedAt: Date, respondBy: Date? = nil) {
        self.id = id
        self.state = state
        self.amount = amount
        self.openedAt = openedAt
        self.respondBy = respondBy
    }
}

public enum ChargebackState: String, Codable, Sendable, CaseIterable {
    case opened        = "OPENED"
    case represented   = "REPRESENTED"
    case arbitration   = "ARBITRATION"
    case wonByCardholder = "WON_BY_CARDHOLDER"
    case wonByMerchant = "WON_BY_MERCHANT"
    case unknown       = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChargebackState(rawValue: raw) ?? .unknown
    }
}

// MARK: - Défaut fermé

/// Ne rend aucune transaction et n'ouvre aucun litige.
public struct ClosedCardTransactionProvider: CardTransactionProviding {

    public init() {}

    public func transactions(cardID: String, cursor: String?) async -> Result<[CardTransaction], FinanceError> { .failure(.capabilityUnavailable) }
    public func transaction(id: String) async -> Result<CardTransaction, FinanceError> { .failure(.capabilityUnavailable) }
    public func reportUnrecognized(transactionID: String, idempotency: IdempotencyContext,
                                   stepUp: StepUpAttestation?) async -> Result<CardDispute, FinanceError> { .failure(.capabilityUnavailable) }
    public func openDispute(_ request: CardDisputeRequest, idempotency: IdempotencyContext,
                            stepUp: StepUpAttestation?) async -> Result<CardDispute, FinanceError> { .failure(.capabilityUnavailable) }
    public func dispute(id: String) async -> Result<CardDispute, FinanceError> { .failure(.capabilityUnavailable) }
    public func disputes(cursor: String?) async -> Result<[CardDispute], FinanceError> { .failure(.capabilityUnavailable) }
}
