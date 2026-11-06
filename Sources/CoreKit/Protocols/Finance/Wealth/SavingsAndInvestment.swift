//
//  SavingsAndInvestment.swift
//  CoreKit
//
//  Épargne et investissement — Bloc 5, chapitres 40 et 41 (GAP5-07).
//
//  **BACKEND CONTRACT REQUIRED** — pockets, objectifs, produits, ordres.
//

import Foundation

// MARK: - Épargne

/// Pockets, vaults et objectifs d'épargne.
public protocol SavingsManaging: Sendable {

    func pockets() async -> Result<[SavingsPocket], FinanceError>

    func create(_ draft: SavingsPocketDraft,
                idempotency: IdempotencyContext) async -> Result<SavingsPocket, FinanceError>

    /// Alimente un pocket. Le mouvement est **backend** : le client n'ajuste
    /// aucun solde, ni celui du pocket ni celui du portefeuille source.
    func fund(pocketID: String, amount: Money,
              idempotency: IdempotencyContext) async -> Result<SavingsPocket, FinanceError>

    func withdraw(pocketID: String, amount: Money,
                  idempotency: IdempotencyContext,
                  stepUp: StepUpAttestation?) async -> Result<SavingsPocket, FinanceError>

    /// Suspend une règle d'alimentation sans la supprimer — exigé mot pour mot
    /// au §13 : « pause ; reprise ; révocation ».
    func pauseRule(pocketID: String, ruleID: String,
                   idempotency: IdempotencyContext) async -> Result<SavingsPocket, FinanceError>

    func resumeRule(pocketID: String, ruleID: String,
                    idempotency: IdempotencyContext) async -> Result<SavingsPocket, FinanceError>

    func closePocket(_ id: String,
                     idempotency: IdempotencyContext) async -> Result<SavingsPocket, FinanceError>
}

public struct SavingsPocket: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let kind: SavingsPocketKind
    public let currency: String
    public let exponent: Int

    /// Solde **rendu par le serveur**.
    public let balanceMinorUnits: Int64
    public let targetMinorUnits: Int64?
    public let targetDate: Date?

    public let state: SavingsPocketState
    public let rules: [SavingsRule]

    /// Restrictions de retrait — épargne bloquée, échéance.
    public let withdrawalRestrictionKeys: [String]
    public let maturesAt: Date?

    /// Rendement affiché, rendu par le partenaire. **Jamais calculé.**
    public let displayedYieldPercent: Decimal?

    public let asOf: Date

    public init(id: String, name: String, kind: SavingsPocketKind, currency: String,
                exponent: Int, balanceMinorUnits: Int64, targetMinorUnits: Int64? = nil,
                targetDate: Date? = nil, state: SavingsPocketState,
                rules: [SavingsRule] = [], withdrawalRestrictionKeys: [String] = [],
                maturesAt: Date? = nil, displayedYieldPercent: Decimal? = nil, asOf: Date) {
        self.id = id
        self.name = name
        self.kind = kind
        self.currency = currency
        self.exponent = exponent
        self.balanceMinorUnits = balanceMinorUnits
        self.targetMinorUnits = targetMinorUnits
        self.targetDate = targetDate
        self.state = state
        self.rules = rules
        self.withdrawalRestrictionKeys = withdrawalRestrictionKeys
        self.maturesAt = maturesAt
        self.displayedYieldPercent = displayedYieldPercent
        self.asOf = asOf
    }
}

public enum SavingsPocketKind: String, Codable, Sendable, CaseIterable {
    case pocket, vault, lockedSavings, partnerProduct, groupGoal, tontine
}

public enum SavingsPocketState: String, Codable, Sendable, CaseIterable {
    case active, paused, matured, closing, closed, restricted

    /// Un état inconnu devient `restricted` : consultable, sans mouvement.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SavingsPocketState(rawValue: raw) ?? .restricted
    }

    public var allowsMovement: Bool { self == .active }
}

public struct SavingsPocketDraft: Sendable, Hashable, Codable {
    public let name: String
    public let kind: SavingsPocketKind
    public let currency: String
    public let targetMinorUnits: Int64?
    public let targetDate: Date?

    public init(name: String, kind: SavingsPocketKind, currency: String,
                targetMinorUnits: Int64? = nil, targetDate: Date? = nil) {
        self.name = name
        self.kind = kind
        self.currency = currency
        self.targetMinorUnits = targetMinorUnits
        self.targetDate = targetDate
    }
}

/// Règle d'alimentation. Une autorisation récurrente : même exigence de
/// consentement et de révocabilité qu'un mandat.
public struct SavingsRule: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: SavingsRuleKind
    public let amountMinorUnits: Int64?
    public let frequency: MandateFrequency?
    public let isPaused: Bool
    public let consentVersion: String
    public let consentEvidenceID: String
    /// Dernier échec d'alimentation, en clé de message — solde insuffisant,
    /// mandat expiré. Exigé au §13.
    public let lastFailureKey: String?

    public init(id: String, kind: SavingsRuleKind, amountMinorUnits: Int64? = nil,
                frequency: MandateFrequency? = nil, isPaused: Bool,
                consentVersion: String, consentEvidenceID: String,
                lastFailureKey: String? = nil) {
        self.id = id
        self.kind = kind
        self.amountMinorUnits = amountMinorUnits
        self.frequency = frequency
        self.isPaused = isPaused
        self.consentVersion = consentVersion
        self.consentEvidenceID = consentEvidenceID
        self.lastFailureKey = lastFailureKey
    }
}

public enum SavingsRuleKind: String, Codable, Sendable, CaseIterable {
    case manual, scheduled, roundUp, challenge
}

public extension SavingsPocket {

    var balance: Money {
        Money(minorUnits: balanceMinorUnits,
              currency: CurrencyCode(code: currency, exponent: exponent))
    }

    /// Progression vers l'objectif, en pourcentage.
    ///
    /// C'est un **ratio d'affichage**, pas une valeur financière : il ne produit
    /// aucun montant et n'engage rien. `nil` sans objectif.
    var progressPercent: Decimal? {
        guard let targetMinorUnits, targetMinorUnits > 0 else { return nil }
        return min(100, Decimal(balanceMinorUnits) / Decimal(targetMinorUnits) * 100)
    }

    /// `true` si un retrait peut être **proposé**.
    ///
    /// La décision reste backend ; ceci évite de proposer un geste voué au refus.
    func allowsWithdrawal(asOf now: Date = Date()) -> Bool {
        guard state.allowsMovement, withdrawalRestrictionKeys.isEmpty else { return false }
        if let maturesAt, now < maturesAt { return false }
        return true
    }
}

// MARK: - Investissement

public protocol InvestmentTrading: Sendable {

    /// Produits accessibles — filtrés par le backend selon la juridiction et
    /// le profil investisseur.
    func products() async -> Result<[InvestmentProduct], FinanceError>

    /// Profil investisseur. `nil` ⇒ non établi, et **rien n'est souscriptible**.
    func investorProfile() async -> Result<InvestorProfile?, FinanceError>

    func placeOrder(_ draft: InvestmentOrderDraft,
                    idempotency: IdempotencyContext,
                    stepUp: StepUpAttestation?) async -> Result<InvestmentOrder, FinanceError>

    func order(_ id: String) async -> Result<InvestmentOrder, FinanceError>

    func cancelOrder(_ id: String,
                     idempotency: IdempotencyContext) async -> Result<InvestmentOrder, FinanceError>

    func portfolio() async -> Result<[InvestmentHolding], FinanceError>
}

public struct InvestmentProduct: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: InvestmentProductKind
    public let issuerID: String
    public let managerID: String?
    public let name: String
    public let currency: String

    /// Exposant décimal de `currency`, **rendu par le backend**.
    ///
    /// `SavingsPocket` le porte déjà ; l'omettre ici obligeait l'écran de
    /// souscription à le supposer nul, ce qui divisait par cent tout montant
    /// libellé dans une devise à deux décimales.
    public let exponent: Int

    public let feeKeys: [String]
    public let riskLevelKey: String
    /// Performance **passée**, rendue par l'émetteur.
    ///
    /// Le champ est nommé sans ambiguïté et l'interface doit l'afficher comme
    /// tel : présenter une performance future comme garantie est interdit (§14),
    /// et le nom du champ est la première défense contre cette dérive.
    public let pastPerformanceKeys: [String]
    public let documentIDs: [String]

    /// Niveau de profil minimum requis pour souscrire.
    public let minimumSuitabilityLevel: Int

    public init(id: String, kind: InvestmentProductKind, issuerID: String,
                managerID: String? = nil, name: String,
                currency: String, exponent: Int,
                feeKeys: [String] = [], riskLevelKey: String,
                pastPerformanceKeys: [String] = [], documentIDs: [String] = [],
                minimumSuitabilityLevel: Int) {
        self.id = id
        self.kind = kind
        self.issuerID = issuerID
        self.managerID = managerID
        self.name = name
        self.currency = currency
        self.exponent = exponent
        self.feeKeys = feeKeys
        self.riskLevelKey = riskLevelKey
        self.pastPerformanceKeys = pastPerformanceKeys
        self.documentIDs = documentIDs
        self.minimumSuitabilityLevel = minimumSuitabilityLevel
    }
}

public enum InvestmentProductKind: String, Codable, Sendable, CaseIterable {
    case termDeposit, fund, bond, security
}

/// Profil investisseur, **établi par le backend**.
public struct InvestorProfile: Codable, Sendable, Hashable {
    public let suitabilityLevel: Int
    public let horizonKey: String
    public let riskToleranceKey: String
    public let establishedAt: Date
    public let expiresAt: Date?

    public init(suitabilityLevel: Int, horizonKey: String, riskToleranceKey: String,
                establishedAt: Date, expiresAt: Date? = nil) {
        self.suitabilityLevel = suitabilityLevel
        self.horizonKey = horizonKey
        self.riskToleranceKey = riskToleranceKey
        self.establishedAt = establishedAt
        self.expiresAt = expiresAt
    }

    public func isValid(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return true }
        return now < expiresAt
    }
}

public struct InvestmentOrderDraft: Sendable, Hashable, Codable {
    public let productID: String
    public let side: InvestmentOrderSide
    public let amount: Money
    /// Consentement aux divulgations de risque de **cette version**.
    public let riskDisclosureVersion: String
    public let hasAcknowledgedRisk: Bool

    public init(productID: String, side: InvestmentOrderSide, amount: Money,
                riskDisclosureVersion: String, hasAcknowledgedRisk: Bool) {
        self.productID = productID
        self.side = side
        self.amount = amount
        self.riskDisclosureVersion = riskDisclosureVersion
        self.hasAcknowledgedRisk = hasAcknowledgedRisk
    }

    public var isSubmittable: Bool {
        hasAcknowledgedRisk && !riskDisclosureVersion.isEmpty && amount.minorUnits > 0
    }
}

public enum InvestmentOrderSide: String, Codable, Sendable { case subscribe, redeem }

public struct InvestmentOrder: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let reference: FinancialReference
    public let productID: String
    public let side: InvestmentOrderSide
    public let requestedAmount: Money
    public let executedAmount: Money?
    public let state: InvestmentOrderState
    public let executionReceiptID: String?
    public let placedAt: Date

    public init(id: String, reference: FinancialReference, productID: String,
                side: InvestmentOrderSide, requestedAmount: Money,
                executedAmount: Money? = nil, state: InvestmentOrderState,
                executionReceiptID: String? = nil, placedAt: Date) {
        self.id = id
        self.reference = reference
        self.productID = productID
        self.side = side
        self.requestedAmount = requestedAmount
        self.executedAmount = executedAmount
        self.state = state
        self.executionReceiptID = executionReceiptID
        self.placedAt = placedAt
    }
}

/// États d'ordre (§14).
public enum InvestmentOrderState: String, Codable, Sendable, CaseIterable {
    case draft, submitted, pending, partiallyExecuted, executed, rejected, cancelled

    /// Un état inconnu devient `pending` : ni exécuté, ni rejeté.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InvestmentOrderState(rawValue: raw) ?? .pending
    }

    public var isTerminal: Bool {
        self == .executed || self == .rejected || self == .cancelled
    }
}

public struct InvestmentHolding: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let productID: String
    public let units: Decimal
    /// Valorisation **rendue par le partenaire**, avec sa date.
    public let valuation: Money
    public let valuedAt: Date

    public init(id: String, productID: String, units: Decimal,
                valuation: Money, valuedAt: Date) {
        self.id = id
        self.productID = productID
        self.units = units
        self.valuation = valuation
        self.valuedAt = valuedAt
    }
}

public extension InvestmentProduct {

    /// `true` si ce profil permet de **proposer** ce produit.
    ///
    /// Le gating de suitability appartient au backend ; ceci évite d'afficher
    /// un produit qu'il refusera, et rend la règle testable.
    func isSuitable(for profile: InvestorProfile?, asOf now: Date = Date()) -> Bool {
        guard let profile, profile.isValid(asOf: now) else { return false }
        return profile.suitabilityLevel >= minimumSuitabilityLevel
    }
}
