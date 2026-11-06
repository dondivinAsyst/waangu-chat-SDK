//
//  CreditLending.swift
//  CoreKit
//
//  Crédit — Bloc 5, chapitres 38 et 39 (GAP5-06).
//
//  **BACKEND CONTRACT REQUIRED** — catalogue, simulation, demande, offre,
//  décaissement, remboursement.
//

import Foundation

/// Découverte, demande et suivi du crédit.
///
/// **Le client ne calcule ni score, ni capacité, ni risque, ni intérêt, ni
/// mensualité contractuelle** (§11). Tous ces nombres arrivent du prêteur. Le
/// Chat les affiche, les compare quand le backend a fourni une base
/// comparable, et collecte le consentement.
public protocol CreditLending: Sendable {

    /// Produits de crédit disponibles.
    func catalog() async -> Result<[CreditProduct], FinanceError>

    /// Simulation **indicative**, calculée backend.
    ///
    /// Le résultat n'est ni une offre, ni une promesse : `CreditSimulation`
    /// porte `isIndicativeOnly` pour que l'interface ne puisse pas l'oublier.
    func simulate(_ request: CreditSimulationRequest) async -> Result<CreditSimulation, FinanceError>

    /// Éligibilité indicative, avec facteurs explicables.
    func eligibility(productID: String) async -> Result<CreditEligibility, FinanceError>

    func apply(_ draft: CreditApplicationDraft,
               idempotency: IdempotencyContext) async -> Result<CreditApplication, FinanceError>

    func application(_ id: String) async -> Result<CreditApplication, FinanceError>

    /// Accepte une offre. Exige le consentement au texte **de cette version**.
    func acceptOffer(applicationID: String, offerID: String,
                     consentVersion: String,
                     idempotency: IdempotencyContext,
                     stepUp: StepUpAttestation?) async -> Result<CreditApplication, FinanceError>

    /// Devis de remboursement anticipé — **calculé backend**.
    func earlyRepaymentQuote(creditID: String) async -> Result<FinancialQuote, FinanceError>
}

// MARK: - Produit

public struct CreditProduct: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: CreditKind
    public let lenderID: String
    public let lenderDisplayName: String
    public let country: String
    public let currency: String

    public let minAmount: Decimal
    public let maxAmount: Decimal
    public let minTermMonths: Int
    public let maxTermMonths: Int

    /// Taux **affiché**, à titre indicatif. Le taux contractuel est celui de
    /// l'offre, et lui seul engage.
    public let displayedRatePercent: Decimal?
    public let disclosureDocumentID: String?

    public init(id: String, kind: CreditKind, lenderID: String, lenderDisplayName: String,
                country: String, currency: String, minAmount: Decimal, maxAmount: Decimal,
                minTermMonths: Int, maxTermMonths: Int,
                displayedRatePercent: Decimal? = nil, disclosureDocumentID: String? = nil) {
        self.id = id
        self.kind = kind
        self.lenderID = lenderID
        self.lenderDisplayName = lenderDisplayName
        self.country = country
        self.currency = currency
        self.minAmount = minAmount
        self.maxAmount = maxAmount
        self.minTermMonths = minTermMonths
        self.maxTermMonths = maxTermMonths
        self.displayedRatePercent = displayedRatePercent
        self.disclosureDocumentID = disclosureDocumentID
    }
}

public enum CreditKind: String, Codable, Sendable, CaseIterable {
    case advance, microcredit, personal, school, health, agricultural
    case equipment, merchant, bnpl, overdraft, creditLine, secured

    /// Un type inconnu fait échouer le décodage : les régimes juridiques
    /// diffèrent, et présenter un BNPL comme un crédit personnel changerait les
    /// divulgations exigées.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = CreditKind(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Type de crédit inconnu : \(raw)")
            )
        }
        self = value
    }
}

// MARK: - Simulation

public struct CreditSimulationRequest: Sendable, Hashable, Codable {
    public let productID: String
    public let amount: Decimal
    public let termMonths: Int

    public init(productID: String, amount: Decimal, termMonths: Int) {
        self.productID = productID
        self.amount = amount
        self.termMonths = termMonths
    }
}

/// Résultat d'une simulation. **Tous les nombres viennent du backend.**
public struct CreditSimulation: Codable, Sendable, Hashable {
    public let productID: String
    public let amount: Decimal
    public let termMonths: Int
    public let monthlyPayment: Decimal
    public let totalCost: Decimal
    public let effectiveRatePercent: Decimal
    public let currency: String

    /// **Toujours vrai dans une simulation.** Le champ existe pour que
    /// l'interface ne puisse pas présenter ceci comme une offre : une
    /// simulation n'engage aucun prêteur.
    public let isIndicativeOnly: Bool

    public init(productID: String, amount: Decimal, termMonths: Int,
                monthlyPayment: Decimal, totalCost: Decimal,
                effectiveRatePercent: Decimal, currency: String,
                isIndicativeOnly: Bool = true) {
        self.productID = productID
        self.amount = amount
        self.termMonths = termMonths
        self.monthlyPayment = monthlyPayment
        self.totalCost = totalCost
        self.effectiveRatePercent = effectiveRatePercent
        self.currency = currency
        self.isIndicativeOnly = isIndicativeOnly
    }
}

/// Éligibilité indicative et ses facteurs.
public struct CreditEligibility: Codable, Sendable, Hashable {
    public let productID: String
    public let isLikelyEligible: Bool
    /// Facteurs explicables, en clés de message. **Jamais un score brut** :
    /// afficher « 62/100 » sans le cadre du prêteur invite à des conclusions
    /// que le client n'a pas les moyens de justifier.
    public let factorKeys: [String]
    public let missingDocumentKeys: [String]

    public init(productID: String, isLikelyEligible: Bool,
                factorKeys: [String] = [], missingDocumentKeys: [String] = []) {
        self.productID = productID
        self.isLikelyEligible = isLikelyEligible
        self.factorKeys = factorKeys
        self.missingDocumentKeys = missingDocumentKeys
    }
}

// MARK: - Demande

public struct CreditApplicationDraft: Sendable, Hashable, Codable {
    public let productID: String
    public let amount: Decimal
    public let termMonths: Int
    public let purposeKey: String?
    public let documentReferences: [String]
    /// Consentement au partage des données avec le prêteur. Sans défaut.
    public let hasConsentedToDataSharing: Bool
    public let consentVersion: String

    public init(productID: String, amount: Decimal, termMonths: Int,
                purposeKey: String? = nil, documentReferences: [String] = [],
                hasConsentedToDataSharing: Bool, consentVersion: String) {
        self.productID = productID
        self.amount = amount
        self.termMonths = termMonths
        self.purposeKey = purposeKey
        self.documentReferences = documentReferences
        self.hasConsentedToDataSharing = hasConsentedToDataSharing
        self.consentVersion = consentVersion
    }

    public var isSubmittable: Bool {
        hasConsentedToDataSharing && !consentVersion.isEmpty && amount > 0 && termMonths > 0
    }
}

public struct CreditApplication: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let reference: FinancialReference
    public let productID: String
    public let state: CreditApplicationState
    public let offer: CreditOffer?
    /// Documents encore attendus, en clés de message.
    public let requiredActionKeys: [String]
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, reference: FinancialReference, productID: String,
                state: CreditApplicationState, offer: CreditOffer? = nil,
                requiredActionKeys: [String] = [], createdAt: Date, updatedAt: Date) {
        self.id = id
        self.reference = reference
        self.productID = productID
        self.state = state
        self.offer = offer
        self.requiredActionKeys = requiredActionKeys
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Offre

public struct CreditOffer: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let approvedAmount: Decimal
    public let currency: String
    public let termMonths: Int
    public let ratePercent: Decimal
    public let totalCost: Decimal
    public let fees: [QuoteFee]
    public let insuranceAmount: Decimal?
    public let schedule: [CreditInstalment]
    public let collateralKeys: [String]
    public let penaltyKeys: [String]
    /// **Une offre expire.** Sans échéance, un prêteur serait engagé
    /// indéfiniment sur des conditions qui ne sont plus les siennes.
    public let expiresAt: Date
    public let disclosureDocumentID: String
    public let consentVersion: String

    public init(id: String, approvedAmount: Decimal, currency: String, termMonths: Int,
                ratePercent: Decimal, totalCost: Decimal, fees: [QuoteFee] = [],
                insuranceAmount: Decimal? = nil, schedule: [CreditInstalment] = [],
                collateralKeys: [String] = [], penaltyKeys: [String] = [],
                expiresAt: Date, disclosureDocumentID: String, consentVersion: String) {
        self.id = id
        self.approvedAmount = approvedAmount
        self.currency = currency
        self.termMonths = termMonths
        self.ratePercent = ratePercent
        self.totalCost = totalCost
        self.fees = fees
        self.insuranceAmount = insuranceAmount
        self.schedule = schedule
        self.collateralKeys = collateralKeys
        self.penaltyKeys = penaltyKeys
        self.expiresAt = expiresAt
        self.disclosureDocumentID = disclosureDocumentID
        self.consentVersion = consentVersion
    }

    public func isExpired(asOf now: Date = Date()) -> Bool { now >= expiresAt }
    public func isAcceptable(asOf now: Date = Date()) -> Bool { !isExpired(asOf: now) }
}

/// Une échéance de l'échéancier. **Rendue par le prêteur, jamais calculée.**
public struct CreditInstalment: Codable, Sendable, Hashable {
    public let number: Int
    public let dueDate: Date
    public let principal: Decimal
    public let interest: Decimal
    public let total: Decimal
    public let state: InstalmentState

    public enum InstalmentState: String, Codable, Sendable {
        case scheduled, paid, late, partiallyPaid, waived
    }

    public init(number: Int, dueDate: Date, principal: Decimal, interest: Decimal,
                total: Decimal, state: InstalmentState) {
        self.number = number
        self.dueDate = dueDate
        self.principal = principal
        self.interest = interest
        self.total = total
        self.state = state
    }
}

// MARK: - États (§12)

public enum CreditApplicationState: String, Codable, Sendable, CaseIterable {
    case draft               = "DRAFT"
    case submitted           = "SUBMITTED"
    case underReview         = "UNDER_REVIEW"
    case actionRequired      = "ACTION_REQUIRED"
    case approved            = "APPROVED"
    case declined            = "DECLINED"
    case offerIssued         = "OFFER_ISSUED"
    case offerExpired        = "OFFER_EXPIRED"
    case accepted            = "ACCEPTED"
    case disbursementPending = "DISBURSEMENT_PENDING"
    case active              = "ACTIVE"
    case closed              = "CLOSED"

    /// Un état inconnu devient `underReview` : ni approuvé — ce qui promettrait
    /// un crédit — ni refusé, ce qui fermerait une demande peut-être vivante.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CreditApplicationState(rawValue: raw) ?? .underReview
    }

    public var isTerminal: Bool { self == .declined || self == .closed }
}

public enum CreditApplicationStateMachine {

    private static let allowed: [CreditApplicationState: Set<CreditApplicationState>] = [
        .draft:               [.submitted],
        .submitted:           [.underReview, .declined],
        .underReview:         [.actionRequired, .approved, .declined],
        .actionRequired:      [.underReview, .declined],
        .approved:            [.offerIssued, .declined],
        .offerIssued:         [.accepted, .offerExpired, .declined],
        .offerExpired:        [.underReview],
        .accepted:            [.disbursementPending, .declined],
        .disbursementPending: [.active, .declined],
        .active:              [.closed],
        .declined:            [],
        .closed:              []
    ]

    public static func isAllowed(from current: CreditApplicationState,
                                 to next: CreditApplicationState) -> Bool {
        if current == next { return true }
        return allowed[current]?.contains(next) ?? false
    }
}
