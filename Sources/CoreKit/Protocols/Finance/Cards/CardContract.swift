//
//  CardContract.swift
//  CoreKit
//
//  Cartes — Bloc 6, chapitre 48 (§21, §22).
//
//  **BACKEND CONTRACT REQUIRED** — émission, activation, contrôles,
//  remplacement, provisioning wallet.
//

import Foundation

/// Cartes physiques et virtuelles.
///
/// **La vérité carte appartient au Card System.** Cette surface consulte et
/// commande ; elle ne connaît ni le PAN, ni le cryptogramme, ni le secret de
/// tokenisation, et n'a aucun moyen de les représenter — voir
/// ``SafeCardPresentation``, dont l'absence de champs est le contrôle.
public protocol CardManaging: Sendable {

    /// Produits de carte accessibles, filtrés par le backend.
    func products() async -> Result<[CardProduct], FinanceError>

    /// Éligibilité à un produit, avec facteurs explicables.
    func eligibility(productID: String) async -> Result<CardEligibility, FinanceError>

    /// Cartes détenues.
    func cards() async -> Result<[SafeCardPresentation], FinanceError>

    /// Détail d'une carte, contrôles compris.
    func card(id: String) async -> Result<CardDetail, FinanceError>

    /// Demande l'émission d'une carte.
    func requestIssuance(
        productID: String,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<SafeCardPresentation, FinanceError>

    /// Active une carte reçue.
    func activate(
        cardID: String,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<SafeCardPresentation, FinanceError>

    /// Gèle ou dégèle. **Le gel doit être instantané et sans friction** : c'est
    /// le geste qu'on fait en découvrant une fraude, et une confirmation de plus
    /// coûte les secondes pendant lesquelles la carte reste utilisable.
    func setFrozen(
        cardID: String,
        isFrozen: Bool,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<SafeCardPresentation, FinanceError>

    /// Applique des contrôles — plafonds, canaux, catégories.
    func applyControls(
        cardID: String,
        controls: CardControls,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<CardDetail, FinanceError>

    /// Remplace une carte perdue, volée ou compromise.
    func replace(
        cardID: String,
        reason: CardReplacementReason,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<SafeCardPresentation, FinanceError>

    /// Prépare l'ajout à un wallet.
    ///
    /// Rend une **capacité**, pas un secret : les données de provisioning ne
    /// transitent jamais par cette couche.
    func provisioningCapability(
        cardID: String
    ) async -> Result<CardProvisioningCapability, FinanceError>
}

// MARK: - Surface sûre (§21)

/// Ce qu'une carte peut montrer.
///
/// **Cette structure n'a aucun champ sensible, et c'est le contrôle.** Un
/// `SafeCardPresentation` ne peut pas transporter un PAN, un CVV, un PIN, un
/// OTP, un jeton complet, un cryptogramme ni une clé : ces champs n'existent
/// pas. Une revue de code peut oublier une règle ; un type ne peut pas porter
/// ce qu'il ne déclare pas.
public struct SafeCardPresentation: Codable, Sendable, Hashable, Identifiable {

    public let id: String

    /// Réseau — visa, mastercard. Chaîne libre : un réseau nouveau ne doit pas
    /// faire échouer le décodage de toute la liste des cartes.
    public let brand: String

    /// **Quatre derniers chiffres uniquement.** Suffit à reconnaître sa carte,
    /// ne suffit à personne pour s'en servir.
    public let last4: String

    public let status: CardStatus
    public let form: CardForm
    public let currency: String

    /// Nom donné par l'utilisateur.
    public let nickname: String?

    /// Échéance affichable — mois et année. Le jour n'existe pas sur une carte.
    public let expiryMonth: Int?
    public let expiryYear: Int?

    /// La carte est-elle déjà dans un wallet de cet appareil ?
    public let isProvisionedOnThisDevice: Bool

    public init(id: String, brand: String, last4: String, status: CardStatus,
                form: CardForm, currency: String, nickname: String? = nil,
                expiryMonth: Int? = nil, expiryYear: Int? = nil,
                isProvisionedOnThisDevice: Bool = false) {
        self.id = id
        self.brand = brand
        self.last4 = last4
        self.status = status
        self.form = form
        self.currency = currency
        self.nickname = nickname
        self.expiryMonth = expiryMonth
        self.expiryYear = expiryYear
        self.isProvisionedOnThisDevice = isProvisionedOnThisDevice
    }

    /// Libellé de reconnaissance, sans rien exposer.
    public var maskedLabel: String { "•••• \(last4)" }
}

public enum CardForm: String, Codable, Sendable, CaseIterable {
    case physical   = "PHYSICAL"
    case virtual    = "VIRTUAL"
    case singleUse  = "SINGLE_USE"
    case unknown    = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardForm(rawValue: raw) ?? .unknown
    }
}

// MARK: - État de la carte

/// États d'une carte.
///
/// Distincts de ceux d'une **transaction** : une carte active peut porter une
/// transaction refusée, et une carte gelée garde son historique. Les confondre
/// ferait disparaître les opérations passées au premier gel.
public enum CardStatus: String, Codable, Sendable, CaseIterable {
    case requested   = "REQUESTED"
    case issued      = "ISSUED"
    case shipped     = "SHIPPED"
    case active      = "ACTIVE"
    case frozen      = "FROZEN"
    case blocked     = "BLOCKED"
    case expired     = "EXPIRED"
    case replaced    = "REPLACED"
    case cancelled   = "CANCELLED"

    /// État connu du backend mais pas de ce client. **Aucune opération.**
    case unknown     = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardStatus(rawValue: raw) ?? .unknown
    }

    /// La carte peut payer.
    public var canTransact: Bool { self == .active }

    /// Le gel a encore un sens.
    public var isFreezable: Bool { self == .active }

    /// Le dégel a encore un sens. Une carte **bloquée** ne se dégèle pas :
    /// le blocage vient de l'émetteur, pas de l'utilisateur, et laisser croire
    /// le contraire produit un geste sans effet.
    public var isUnfreezable: Bool { self == .frozen }

    /// Le remplacement a encore un sens.
    public var isReplaceable: Bool {
        switch self {
        case .active, .frozen, .blocked, .expired: return true
        default: return false
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .replaced, .cancelled, .expired: return true
        default: return false
        }
    }
}

// MARK: - Détail et contrôles

public struct CardDetail: Codable, Sendable, Hashable, Identifiable {

    public var id: String { presentation.id }
    public let presentation: SafeCardPresentation
    public let controls: CardControls

    /// Plafonds réellement appliqués, **rendus par l'émetteur**.
    ///
    /// Ils peuvent différer de ceux demandés : le produit impose ses propres
    /// bornes. Afficher la demande comme si elle était appliquée ferait croire
    /// à un plafond qui n'existe pas.
    public let effectiveLimits: [CardLimit]

    public let productID: String
    public let issuedAt: Date?

    public init(presentation: SafeCardPresentation, controls: CardControls,
                effectiveLimits: [CardLimit] = [], productID: String, issuedAt: Date? = nil) {
        self.presentation = presentation
        self.controls = controls
        self.effectiveLimits = effectiveLimits
        self.productID = productID
        self.issuedAt = issuedAt
    }
}

/// Ce que l'utilisateur peut restreindre lui-même.
public struct CardControls: Codable, Sendable, Hashable {

    /// Canaux autorisés. Vide ⇒ **aucun canal**, pas « tous » : une liste vide
    /// mal interprétée ouvrirait la carte partout.
    public let allowedChannels: Set<CardChannel>

    /// Catégories marchandes bloquées, par code MCC.
    public let blockedMerchantCategories: Set<String>

    /// Paiements hors du pays de résidence.
    public let allowsInternational: Bool

    /// Retraits en distributeur.
    public let allowsATM: Bool

    /// Plafonds demandés. Les plafonds **appliqués** sont dans `CardDetail`.
    public let requestedLimits: [CardLimit]

    public init(allowedChannels: Set<CardChannel>, blockedMerchantCategories: Set<String> = [],
                allowsInternational: Bool, allowsATM: Bool, requestedLimits: [CardLimit] = []) {
        self.allowedChannels = allowedChannels
        self.blockedMerchantCategories = blockedMerchantCategories
        self.allowsInternational = allowsInternational
        self.allowsATM = allowsATM
        self.requestedLimits = requestedLimits
    }
}

public enum CardChannel: String, Codable, Sendable, CaseIterable {
    case online       = "ONLINE"
    case inStore      = "IN_STORE"
    case contactless  = "CONTACTLESS"
    case atm          = "ATM"
    case recurring    = "RECURRING"
}

public struct CardLimit: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(period.rawValue)-\(scope.rawValue)" }
    public let period: CardLimitPeriod
    public let scope: CardLimitScope
    public let amount: Money

    public init(period: CardLimitPeriod, scope: CardLimitScope, amount: Money) {
        self.period = period
        self.scope = scope
        self.amount = amount
    }
}

public enum CardLimitPeriod: String, Codable, Sendable, CaseIterable {
    case perTransaction = "PER_TRANSACTION"
    case daily          = "DAILY"
    case weekly         = "WEEKLY"
    case monthly        = "MONTHLY"
}

public enum CardLimitScope: String, Codable, Sendable, CaseIterable {
    case all           = "ALL"
    case atm           = "ATM"
    case online        = "ONLINE"
    case international = "INTERNATIONAL"
}

public enum CardReplacementReason: String, Codable, Sendable, CaseIterable {
    case lost      = "LOST"
    case stolen    = "STOLEN"
    case damaged   = "DAMAGED"
    case compromised = "COMPROMISED"
    case expired   = "EXPIRED"

    /// Une carte volée ou compromise doit être **bloquée**, pas seulement
    /// remplacée : l'ancienne reste utilisable jusqu'à la réception de la
    /// nouvelle, et c'est précisément la fenêtre que la fraude exploite.
    public var requiresImmediateBlock: Bool {
        self == .stolen || self == .compromised
    }
}

// MARK: - Produit et éligibilité

public struct CardProduct: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let nameKey: String
    public let form: CardForm
    public let currencies: [String]
    public let feeKeys: [String]
    public let isMultiCurrency: Bool
    public let supportsWalletProvisioning: Bool

    public init(id: String, nameKey: String, form: CardForm, currencies: [String],
                feeKeys: [String] = [], isMultiCurrency: Bool = false,
                supportsWalletProvisioning: Bool = false) {
        self.id = id
        self.nameKey = nameKey
        self.form = form
        self.currencies = currencies
        self.feeKeys = feeKeys
        self.isMultiCurrency = isMultiCurrency
        self.supportsWalletProvisioning = supportsWalletProvisioning
    }
}

public struct CardEligibility: Codable, Sendable, Hashable {
    public let productID: String
    public let isLikelyEligible: Bool
    /// Facteurs explicables. **Jamais un score brut.**
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

/// Autorisation d'ajouter la carte à un wallet.
///
/// Ne porte **aucune donnée de provisioning** : seulement le droit de démarrer
/// le parcours, et le handoff vers la mini-app propriétaire qui, elle, détient
/// les secrets.
public struct CardProvisioningCapability: Codable, Sendable, Hashable {
    public let cardID: String
    public let isAvailable: Bool
    public let unavailableReasonKey: String?
    /// Identifiant du parcours de provisioning côté application propriétaire.
    public let handoffID: String?
    public let expiresAt: Date?

    public init(cardID: String, isAvailable: Bool, unavailableReasonKey: String? = nil,
                handoffID: String? = nil, expiresAt: Date? = nil) {
        self.cardID = cardID
        self.isAvailable = isAvailable
        self.unavailableReasonKey = unavailableReasonKey
        self.handoffID = handoffID
        self.expiresAt = expiresAt
    }

    public func isUsable(at now: Date = Date()) -> Bool {
        guard isAvailable, handoffID != nil else { return false }
        if let expiresAt, now >= expiresAt { return false }
        return true
    }
}

// MARK: - Défaut fermé

/// Ne rend aucune carte et n'exécute aucun contrôle.
public struct ClosedCardManager: CardManaging {

    public init() {}

    public func products() async -> Result<[CardProduct], FinanceError> { .failure(.capabilityUnavailable) }
    public func eligibility(productID: String) async -> Result<CardEligibility, FinanceError> { .failure(.capabilityUnavailable) }
    public func cards() async -> Result<[SafeCardPresentation], FinanceError> { .failure(.capabilityUnavailable) }
    public func card(id: String) async -> Result<CardDetail, FinanceError> { .failure(.capabilityUnavailable) }
    public func requestIssuance(productID: String, idempotency: IdempotencyContext,
                                stepUp: StepUpAttestation?) async -> Result<SafeCardPresentation, FinanceError> { .failure(.capabilityUnavailable) }
    public func activate(cardID: String, idempotency: IdempotencyContext,
                         stepUp: StepUpAttestation?) async -> Result<SafeCardPresentation, FinanceError> { .failure(.capabilityUnavailable) }
    public func setFrozen(cardID: String, isFrozen: Bool, idempotency: IdempotencyContext,
                          stepUp: StepUpAttestation?) async -> Result<SafeCardPresentation, FinanceError> { .failure(.capabilityUnavailable) }
    public func applyControls(cardID: String, controls: CardControls, idempotency: IdempotencyContext,
                              stepUp: StepUpAttestation?) async -> Result<CardDetail, FinanceError> { .failure(.capabilityUnavailable) }
    public func replace(cardID: String, reason: CardReplacementReason, idempotency: IdempotencyContext,
                        stepUp: StepUpAttestation?) async -> Result<SafeCardPresentation, FinanceError> { .failure(.capabilityUnavailable) }
    public func provisioningCapability(cardID: String) async -> Result<CardProvisioningCapability, FinanceError> { .failure(.capabilityUnavailable) }
}
