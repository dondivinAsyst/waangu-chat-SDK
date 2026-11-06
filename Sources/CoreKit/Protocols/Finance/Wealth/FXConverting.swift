//
//  FXConverting.swift
//  CoreKit
//
//  FX et wallets multidevises — Bloc 5, chapitre 37 (GAP5-04).
//
//  **BACKEND CONTRACT REQUIRED** — cotation, conversion, alertes.
//

import Foundation

/// Convertit entre devises et expose les portefeuilles.
///
/// **Aucun calcul ici, jamais.** Le §10 l'écrit sans ambiguïté : `amount * rate`
/// ne doit produire aucune valeur financière exécutable. Le taux est transporté,
/// affiché, comparé — jamais appliqué. La gate §28 le vérifie mécaniquement.
public protocol FXConverting: Sendable {

    /// Portefeuilles de l'utilisateur, un par devise.
    func wallets() async -> Result<[CurrencyWallet], FinanceError>

    /// Cotation pour une conversion.
    func quote(
        from source: String, to target: String, sourceAmount: Decimal
    ) async -> Result<FinancialQuote, FinanceError>

    /// Exécute la conversion sur un devis **exécutable et intact**.
    func convert(
        quote: FinancialQuote,
        idempotency: IdempotencyContext
    ) async -> Result<FXConversion, FinanceError>

    /// Règles de conversion automatique. Le consentement est révocable.
    func automaticRules() async -> Result<[FXAutomaticRule], FinanceError>

    func revokeRule(_ ruleID: String,
                    idempotency: IdempotencyContext) async -> Result<Void, FinanceError>
}

// MARK: - Portefeuille

/// Un solde, dans une devise.
///
/// Le solde vient **exclusivement** du serveur : aucune propriété n'est `var`,
/// et aucune méthode ne le fait varier. C'est ce qui rend la gate §27
/// (`balance ±=`) structurellement satisfaite plutôt que respectée par
/// discipline.
public struct CurrencyWallet: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let currency: String
    public let availableMinorUnits: Int64
    /// Fonds engagés mais non encore débités — un envoi financé non soumis.
    public let pendingMinorUnits: Int64
    public let exponent: Int

    /// Horodatage **serveur** du solde. Un solde sans date ne peut pas être
    /// signalé comme daté, et un solde daté affiché comme courant est un
    /// mensonge sur la somme disponible.
    public let asOf: Date

    public let isPrimary: Bool

    public init(id: String, currency: String, availableMinorUnits: Int64,
                pendingMinorUnits: Int64 = 0, exponent: Int, asOf: Date,
                isPrimary: Bool = false) {
        self.id = id
        self.currency = currency
        self.availableMinorUnits = availableMinorUnits
        self.pendingMinorUnits = pendingMinorUnits
        self.exponent = exponent
        self.asOf = asOf
        self.isPrimary = isPrimary
    }
}

public extension CurrencyWallet {

    var available: Money {
        Money(minorUnits: availableMinorUnits,
              currency: CurrencyCode(code: currency, exponent: exponent))
    }

    /// Au-delà, le solde doit être relu avant toute décision.
    static let freshnessWindow: TimeInterval = 60

    func isStale(asOf now: Date = Date()) -> Bool {
        now.timeIntervalSince(self.asOf) > Self.freshnessWindow
    }

    /// `true` si ce montant **paraît** couvert.
    ///
    /// « Paraît » est le mot juste : le client compare deux nombres rendus par
    /// le serveur, il ne décide pas de la disponibilité des fonds. Un solde
    /// périmé ne couvre rien, quel que soit son chiffre.
    func appearsToCover(_ amount: Money, asOf now: Date = Date()) -> Bool {
        guard !isStale(asOf: now), amount.currency.code == currency else { return false }
        return amount.minorUnits <= availableMinorUnits
    }
}

// MARK: - Conversion

public struct FXConversion: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let reference: FinancialReference
    public let quote: FinancialQuote
    public let state: FXConversionState
    public let executedAt: Date?

    public init(id: String, reference: FinancialReference, quote: FinancialQuote,
                state: FXConversionState, executedAt: Date? = nil) {
        self.id = id
        self.reference = reference
        self.quote = quote
        self.state = state
        self.executedAt = executedAt
    }
}

public enum FXConversionState: String, Codable, Sendable, CaseIterable {
    case draft, quoted, quoteExpired, executing, executed, failed, cancelled

    /// Un état inconnu devient `executing` : ni abouti ni échoué, et il appelle
    /// une réconciliation plutôt qu'une conclusion.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FXConversionState(rawValue: raw) ?? .executing
    }

    public var isTerminal: Bool {
        self == .executed || self == .failed || self == .cancelled
    }
}

// MARK: - Règles automatiques

/// Une conversion automatique consentie par l'utilisateur.
///
/// Comme un mandat : c'est une autorisation permanente d'agir sur les fonds.
/// Même exigence de preuve, même révocabilité.
public struct FXAutomaticRule: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let sourceCurrency: String
    public let targetCurrency: String
    public let trigger: FXRuleTrigger

    /// Plafond par exécution. `nil` ⇒ borne côté backend, que le client ne
    /// valide pas.
    public let maxAmountPerExecution: Money?

    public let consentVersion: String
    public let consentEvidenceID: String
    public let isActive: Bool
    public let createdAt: Date

    public init(id: String, sourceCurrency: String, targetCurrency: String,
                trigger: FXRuleTrigger, maxAmountPerExecution: Money? = nil,
                consentVersion: String, consentEvidenceID: String,
                isActive: Bool, createdAt: Date) {
        self.id = id
        self.sourceCurrency = sourceCurrency
        self.targetCurrency = targetCurrency
        self.trigger = trigger
        self.maxAmountPerExecution = maxAmountPerExecution
        self.consentVersion = consentVersion
        self.consentEvidenceID = consentEvidenceID
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

public enum FXRuleTrigger: Codable, Sendable, Hashable {
    /// Convertir dès qu'un solde dépasse un seuil.
    case balanceAbove(minorUnits: Int64)
    /// Convertir quand le taux atteint une valeur — **comparaison, pas calcul**.
    case rateReaches(Decimal)
    case scheduled(MandateFrequency)
}

/// Alerte de taux. Purement informative : elle n'exécute rien.
public struct FXRateAlert: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let sourceCurrency: String
    public let targetCurrency: String
    public let targetRate: Decimal
    public let isActive: Bool

    public init(id: String, sourceCurrency: String, targetCurrency: String,
                targetRate: Decimal, isActive: Bool) {
        self.id = id
        self.sourceCurrency = sourceCurrency
        self.targetCurrency = targetCurrency
        self.targetRate = targetRate
        self.isActive = isActive
    }
}
