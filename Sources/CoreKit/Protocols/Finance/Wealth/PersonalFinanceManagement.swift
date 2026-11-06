//
//  PersonalFinanceManagement.swift
//  CoreKit
//
//  PFM et Copilot financier — Bloc 5, chapitre 42 (GAP5-09).
//
//  **BACKEND CONTRACT REQUIRED** — agrégats, budgets, anomalies.
//

import Foundation

/// Analyses financières personnelles.
///
/// **Tous les agrégats viennent du backend.** Le client n'additionne pas des
/// transactions pour produire un total de dépenses : une somme calculée
/// localement diverge de la comptabilité dès qu'une opération est en vol,
/// annulée ou remboursée, et l'utilisateur verrait deux chiffres différents
/// selon l'écran.
public protocol PersonalFinanceProviding: Sendable {

    func summary(period: PFMPeriod) async -> Result<PFMSummary, FinanceError>
    func budgets() async -> Result<[PFMBudget], FinanceError>

    func createBudget(_ draft: PFMBudgetDraft,
                      idempotency: IdempotencyContext) async -> Result<PFMBudget, FinanceError>

    /// Anomalies détectées **par le backend**.
    func anomalies(period: PFMPeriod) async -> Result<[PFMAnomaly], FinanceError>

    /// Corrige la catégorie d'une opération. Le client transmet la correction,
    /// il ne recatégorise rien.
    func recategorize(operationID: String, categoryID: String,
                      idempotency: IdempotencyContext) async -> Result<Void, FinanceError>
}

// MARK: - Période

public struct PFMPeriod: Sendable, Hashable, Codable {
    public let start: Date
    public let end: Date
    /// Fuseau dans lequel la période a été découpée.
    ///
    /// Sans lui, « les dépenses de janvier » n'a pas de sens stable : une
    /// opération du 31 à 23 h peut tomber en février selon l'observateur.
    public let timeZoneIdentifier: String

    public init(start: Date, end: Date, timeZoneIdentifier: String) {
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

// MARK: - Synthèse

public struct PFMSummary: Codable, Sendable, Hashable {
    public let period: PFMPeriod
    public let currency: String
    public let exponent: Int

    public let totalIncomeMinorUnits: Int64
    public let totalExpenseMinorUnits: Int64
    public let netWorthMinorUnits: Int64?
    public let totalDebtMinorUnits: Int64?

    public let categories: [PFMCategoryTotal]
    public let recurringPayments: [PFMRecurringPayment]

    /// Prévision de trésorerie, **rendue par le backend**.
    public let forecastMinorUnits: Int64?

    public let asOf: Date

    public init(period: PFMPeriod, currency: String, exponent: Int,
                totalIncomeMinorUnits: Int64, totalExpenseMinorUnits: Int64,
                netWorthMinorUnits: Int64? = nil, totalDebtMinorUnits: Int64? = nil,
                categories: [PFMCategoryTotal] = [],
                recurringPayments: [PFMRecurringPayment] = [],
                forecastMinorUnits: Int64? = nil, asOf: Date) {
        self.period = period
        self.currency = currency
        self.exponent = exponent
        self.totalIncomeMinorUnits = totalIncomeMinorUnits
        self.totalExpenseMinorUnits = totalExpenseMinorUnits
        self.netWorthMinorUnits = netWorthMinorUnits
        self.totalDebtMinorUnits = totalDebtMinorUnits
        self.categories = categories
        self.recurringPayments = recurringPayments
        self.forecastMinorUnits = forecastMinorUnits
        self.asOf = asOf
    }
}

public struct PFMCategoryTotal: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let labelKey: String
    public let amountMinorUnits: Int64
    public let isUserDefined: Bool

    public init(id: String, labelKey: String, amountMinorUnits: Int64, isUserDefined: Bool) {
        self.id = id
        self.labelKey = labelKey
        self.amountMinorUnits = amountMinorUnits
        self.isUserDefined = isUserDefined
    }
}

/// Paiement récurrent **détecté par le backend**.
public struct PFMRecurringPayment: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let merchantLabel: String
    public let amountMinorUnits: Int64
    public let frequency: MandateFrequency
    public let nextExpectedAt: Date?
    /// `true` si un mandat le porte — il est alors révocable depuis l'app.
    public let hasRevocableMandate: Bool

    public init(id: String, merchantLabel: String, amountMinorUnits: Int64,
                frequency: MandateFrequency, nextExpectedAt: Date? = nil,
                hasRevocableMandate: Bool) {
        self.id = id
        self.merchantLabel = merchantLabel
        self.amountMinorUnits = amountMinorUnits
        self.frequency = frequency
        self.nextExpectedAt = nextExpectedAt
        self.hasRevocableMandate = hasRevocableMandate
    }
}

// MARK: - Budgets

public struct PFMBudget: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let labelKey: String
    public let categoryID: String?
    public let limitMinorUnits: Int64
    public let spentMinorUnits: Int64
    public let currency: String
    public let period: PFMPeriod
    /// Budget partagé avec d'autres participants.
    public let sharedWithActorIDs: [String]

    public init(id: String, labelKey: String, categoryID: String? = nil,
                limitMinorUnits: Int64, spentMinorUnits: Int64, currency: String,
                period: PFMPeriod, sharedWithActorIDs: [String] = []) {
        self.id = id
        self.labelKey = labelKey
        self.categoryID = categoryID
        self.limitMinorUnits = limitMinorUnits
        self.spentMinorUnits = spentMinorUnits
        self.currency = currency
        self.period = period
        self.sharedWithActorIDs = sharedWithActorIDs
    }

    /// Consommation, en pourcentage. **Ratio d'affichage** : il ne produit
    /// aucune valeur financière et n'engage rien.
    public var usagePercent: Decimal? {
        guard limitMinorUnits > 0 else { return nil }
        return Decimal(spentMinorUnits) / Decimal(limitMinorUnits) * 100
    }

    public var isExceeded: Bool { spentMinorUnits > limitMinorUnits }
}

public struct PFMBudgetDraft: Sendable, Hashable, Codable {
    public let labelKey: String
    public let categoryID: String?
    public let limitMinorUnits: Int64
    public let currency: String
    public let period: PFMPeriod

    public init(labelKey: String, categoryID: String? = nil, limitMinorUnits: Int64,
                currency: String, period: PFMPeriod) {
        self.labelKey = labelKey
        self.categoryID = categoryID
        self.limitMinorUnits = limitMinorUnits
        self.currency = currency
        self.period = period
    }
}

public struct PFMAnomaly: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kindKey: String
    public let operationID: String?
    public let detectedAt: Date
    /// Explication, en clé. Le client ne rédige pas de justification financière.
    public let explanationKey: String

    public init(id: String, kindKey: String, operationID: String? = nil,
                detectedAt: Date, explanationKey: String) {
        self.id = id
        self.kindKey = kindKey
        self.operationID = operationID
        self.detectedAt = detectedAt
        self.explanationKey = explanationKey
    }
}

// MARK: - Copilot borné (§15)

/// Autorisation d'un outil du Copilot.
///
/// Un outil sans autorisation explicite ne s'exécute pas. Le Copilot **propose**
/// une intention ; l'exécution passe par la même chaîne que n'importe quel geste
/// utilisateur — politique, confirmation, step-up, backend.
public struct ToolAuthorization: Sendable, Hashable {
    public let toolID: String
    public let grantedByUser: Bool
    public let capabilityID: String?
    public let correlationID: CorrelationId

    public init(toolID: String, grantedByUser: Bool,
                capabilityID: String? = nil, correlationID: CorrelationId) {
        self.toolID = toolID
        self.grantedByUser = grantedByUser
        self.capabilityID = capabilityID
        self.correlationID = correlationID
    }

    /// Sans accord explicite, rien ne s'exécute.
    public var permitsExecution: Bool { grantedByUser }
}

/// Un outil que le Copilot peut invoquer, dans des bornes.
///
/// **Le Copilot ne peut rien exécuter directement.** Il lit, résume, explique et
/// propose. Toute mutation financière sort de ce protocole et repasse par la
/// chaîne ordinaire — c'est ce que §15 et §30 exigent, et c'est ce que le type
/// rend structurel : `execute` reçoit une autorisation, et un outil de mutation
/// n'en obtient pas sans geste utilisateur.
public protocol PFMBoundedTool: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    /// Identifiant stable, pour l'audit.
    var toolID: String { get }

    /// `true` si l'outil ne fait que lire. Un outil de lecture ne peut pas
    /// débiter, et cette distinction doit être déclarée, pas devinée.
    var isReadOnly: Bool { get }

    func execute(input: Input, authorization: ToolAuthorization) async throws -> Output
}

/// Ce que le Copilot a le droit de répondre.
///
/// Chaque réponse financière doit être **rattachable à une source autorisée**
/// (§15). Une réponse sans source est une invention, et le type ne permet pas
/// d'en construire une.
public struct CopilotAnswer: Sendable, Hashable {
    public let textKey: String
    /// Identifiants des sources ayant produit la réponse. **Jamais vide.**
    public let sourceOperationIDs: [String]
    public let toolID: String
    public let correlationID: CorrelationId

    /// Rend `nil` si aucune source n'étaye la réponse.
    public init?(textKey: String, sourceOperationIDs: [String],
                 toolID: String, correlationID: CorrelationId) {
        guard !sourceOperationIDs.isEmpty else { return nil }
        self.textKey = textKey
        self.sourceOperationIDs = sourceOperationIDs
        self.toolID = toolID
        self.correlationID = correlationID
    }
}
