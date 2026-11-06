//
//  RemittanceSending.swift
//  CoreKit
//
//  Transferts internationaux — Bloc 5, chapitres 34 et 36 (GAP5-01).
//
//  **BACKEND CONTRACT REQUIRED** — corridors, devis, financement, soumission,
//  suivi, annulation, remboursement.
//

import Foundation

/// Envoie de l'argent à l'international.
///
/// **Le corridor décide de tout.** Disponibilité, méthodes de livraison,
/// documents exigés, délais : rien de cela n'est déductible côté client, et
/// l'activation d'un sens n'active jamais l'autre — le §34 l'écrit
/// explicitement : « A→B ne doit jamais activer B→A ».
public protocol RemittanceSending: Sendable {

    /// Corridors ouverts pour cet utilisateur.
    func corridors() async -> Result<[RemittanceCorridor], FinanceError>

    /// Devis pour un corridor donné.
    func quote(_ request: RemittanceQuoteRequest) async -> Result<FinancialQuote, FinanceError>

    /// Crée l'envoi à partir d'un devis **exécutable**.
    func create(
        quote: FinancialQuote,
        recipientID: String,
        idempotency: IdempotencyContext
    ) async -> Result<Remittance, FinanceError>

    /// Finance l'envoi. Séparé de la création : entre les deux, la conformité
    /// peut demander une revue, et l'argent ne doit pas être engagé avant.
    func fund(
        _ id: String,
        method: RemittanceFundingMethod,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<Remittance, FinanceError>

    /// Soumet au partenaire.
    func submit(_ id: String, idempotency: IdempotencyContext) async -> Result<Remittance, FinanceError>

    func track(_ id: String) async -> Result<Remittance, FinanceError>

    /// Annule pendant la fenêtre d'annulation, si le corridor en ouvre une.
    func cancel(_ id: String, idempotency: IdempotencyContext) async -> Result<Remittance, FinanceError>
}

// MARK: - Corridor

public struct RemittanceCorridor: Codable, Sendable, Hashable, Identifiable {

    public var id: String { "\(sourceCountry)->\(targetCountry)" }

    public let sourceCountry: String
    public let targetCountry: String
    public let sourceCurrency: String
    public let targetCurrencies: [String]

    public let partnerID: String
    public let deliveryMethods: [RemittanceDeliveryMethod]

    /// `false` ⇒ affiché avec son motif, jamais masqué en silence.
    public let isAvailable: Bool
    public let unavailableReasonKey: String?

    /// Délai estimé, **rendu par le partenaire**. Une estimation calculée
    /// localement deviendrait une promesse que personne ne tient.
    public let estimatedDeliverySeconds: TimeInterval?

    /// Fenêtre pendant laquelle l'envoi reste annulable. `nil` ⇒ aucune.
    public let cancellationWindowSeconds: TimeInterval?

    public init(
        sourceCountry: String, targetCountry: String,
        sourceCurrency: String, targetCurrencies: [String],
        partnerID: String, deliveryMethods: [RemittanceDeliveryMethod],
        isAvailable: Bool, unavailableReasonKey: String? = nil,
        estimatedDeliverySeconds: TimeInterval? = nil,
        cancellationWindowSeconds: TimeInterval? = nil
    ) {
        self.sourceCountry = sourceCountry
        self.targetCountry = targetCountry
        self.sourceCurrency = sourceCurrency
        self.targetCurrencies = targetCurrencies
        self.partnerID = partnerID
        self.deliveryMethods = deliveryMethods
        self.isAvailable = isAvailable
        self.unavailableReasonKey = unavailableReasonKey
        self.estimatedDeliverySeconds = estimatedDeliverySeconds
        self.cancellationWindowSeconds = cancellationWindowSeconds
    }
}

public enum RemittanceDeliveryMethod: String, Codable, Sendable, CaseIterable {
    case walletCredit = "WALLET_CREDIT"
    case bankDeposit  = "BANK_DEPOSIT"
    case mobileMoney  = "MOBILE_MONEY"
    case cashPickup   = "CASH_PICKUP"

    /// Une méthode inconnue fait échouer le décodage du corridor.
    ///
    /// Pas de repli : proposer « retrait espèces » là où le partenaire fait un
    /// dépôt bancaire enverrait quelqu'un attendre à un guichet pour rien.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = RemittanceDeliveryMethod(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Méthode de livraison inconnue : \(raw)")
            )
        }
        self = value
    }
}

public struct RemittanceQuoteRequest: Sendable, Hashable, Codable {
    public let corridorID: String
    public let deliveryMethod: RemittanceDeliveryMethod
    /// L'un **ou** l'autre, jamais les deux : fixer les deux reviendrait à
    /// imposer un taux, ce qui appartient au backend.
    public let sourceAmount: Decimal?
    public let targetAmount: Decimal?
    public let targetCurrency: String

    public init(corridorID: String, deliveryMethod: RemittanceDeliveryMethod,
                sourceAmount: Decimal?, targetAmount: Decimal?, targetCurrency: String) {
        self.corridorID = corridorID
        self.deliveryMethod = deliveryMethod
        self.sourceAmount = sourceAmount
        self.targetAmount = targetAmount
        self.targetCurrency = targetCurrency
    }

    /// Une demande qui fixe les deux montants, ou aucun, est mal formée.
    public var isWellFormed: Bool {
        (sourceAmount != nil) != (targetAmount != nil)
    }
}

public enum RemittanceFundingMethod: String, Codable, Sendable, CaseIterable {
    case wallet, bankAccount, tokenizedCard
}

// MARK: - L'envoi

public struct Remittance: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let reference: FinancialReference
    public let corridorID: String
    public let state: RemittanceState

    public let quote: FinancialQuote
    public let recipientID: String
    public let deliveryMethod: RemittanceDeliveryMethod

    /// Référence à présenter pour un retrait espèces. **Non secrète** : elle
    /// identifie un envoi attendu, elle n'autorise aucun retrait à elle seule.
    public let pickupReference: String?

    /// Preuve de remise, quand le partenaire la fournit.
    public let deliveryProofID: String?

    public let createdAt: Date
    public let updatedAt: Date
    /// Jusqu'à quand l'annulation reste possible.
    public let cancellableUntil: Date?

    public init(
        id: String, reference: FinancialReference, corridorID: String,
        state: RemittanceState, quote: FinancialQuote, recipientID: String,
        deliveryMethod: RemittanceDeliveryMethod,
        pickupReference: String? = nil, deliveryProofID: String? = nil,
        createdAt: Date, updatedAt: Date, cancellableUntil: Date? = nil
    ) {
        self.id = id
        self.reference = reference
        self.corridorID = corridorID
        self.state = state
        self.quote = quote
        self.recipientID = recipientID
        self.deliveryMethod = deliveryMethod
        self.pickupReference = pickupReference
        self.deliveryProofID = deliveryProofID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cancellableUntil = cancellableUntil
    }
}

// MARK: - États (§7)

public enum RemittanceState: String, Codable, Sendable, CaseIterable {
    case draft             = "DRAFT"
    case quoted            = "QUOTED"
    case quoteExpired      = "QUOTE_EXPIRED"
    case funded            = "FUNDED"
    case complianceReview  = "COMPLIANCE_REVIEW"
    case submitted         = "SUBMITTED"
    case partnerProcessing = "PARTNER_PROCESSING"
    case readyForPickup    = "READY_FOR_PICKUP"
    case delivered         = "DELIVERED"
    case failed            = "FAILED"
    case returned          = "RETURNED"
    case refundPending     = "REFUND_PENDING"
    case refunded          = "REFUNDED"
    case blocked           = "BLOCKED"
    case cancelled         = "CANCELLED"

    /// Un état inconnu devient `complianceReview` : ni abouti, ni échoué, et il
    /// n'autorise aucune action utilisateur. Le repli le plus sûr d'un envoi
    /// international est « quelqu'un regarde ».
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RemittanceState(rawValue: raw) ?? .complianceReview
    }

    public var isTerminal: Bool {
        switch self {
        case .delivered, .failed, .refunded, .cancelled, .blocked: return true
        default: return false
        }
    }

    /// L'argent a quitté le compte de l'émetteur.
    ///
    /// Distinct de « abouti » : à partir de `funded`, un échec devient un
    /// remboursement à suivre, pas une opération sans conséquence.
    public var hasDebitedSender: Bool {
        switch self {
        case .draft, .quoted, .quoteExpired, .cancelled: return false
        default: return true
        }
    }
}

// MARK: - Machine à états

public enum RemittanceStateMachine {

    private static let allowed: [RemittanceState: Set<RemittanceState>] = [
        .draft:             [.quoted, .cancelled],
        .quoted:            [.quoteExpired, .funded, .cancelled, .blocked],
        .quoteExpired:      [.quoted, .cancelled],
        .funded:            [.complianceReview, .submitted, .refundPending, .blocked],
        .complianceReview:  [.submitted, .blocked, .refundPending],
        .submitted:         [.partnerProcessing, .failed, .returned, .blocked],
        .partnerProcessing: [.readyForPickup, .delivered, .failed, .returned],
        .readyForPickup:    [.delivered, .returned, .failed],
        .returned:          [.refundPending],
        .refundPending:     [.refunded, .failed],
        // Terminaux
        .delivered: [], .refunded: [], .cancelled: [], .blocked: [], .failed: [.refundPending]
    ]

    public static func isAllowed(from current: RemittanceState, to next: RemittanceState) -> Bool {
        if current == next { return true }
        return allowed[current]?.contains(next) ?? false
    }
}

// MARK: - Confort

public extension Remittance {

    /// `true` si l'annulation est encore ouverte.
    ///
    /// Deux conditions : la fenêtre court encore, **et** l'état l'autorise. Un
    /// envoi déjà remis ne s'annule pas, même dans la fenêtre.
    func isCancellable(asOf now: Date = Date()) -> Bool {
        guard let cancellableUntil, now < cancellableUntil else { return false }
        return RemittanceStateMachine.isAllowed(from: state, to: .cancelled)
    }

    /// `true` si l'utilisateur doit être informé qu'un remboursement est en jeu.
    var awaitsRefund: Bool {
        state == .returned || state == .refundPending
    }
}

public extension RemittanceCorridor {

    /// `true` si ce corridor peut porter un envoi maintenant.
    func allowsSending(to currency: String) -> Bool {
        isAvailable && targetCurrencies.contains(currency) && !deliveryMethods.isEmpty
    }

    /// **L'ouverture de A→B n'ouvre jamais B→A** (§34).
    ///
    /// Le corridor inverse est un autre objet, avec ses propres licences,
    /// partenaires et méthodes. Cette méthode existe pour rendre la règle
    /// testable, pas pour dériver le corridor inverse.
    var reversedIdentity: String { "\(targetCountry)->\(sourceCountry)" }
}
