//
//  FinancialQuote.swift
//  CoreKit
//
//  Devis financier immuable — Bloc 5 §8 (GAP5-02).
//

import Foundation
import CryptoKit

/// Un devis rendu par le backend. **Immuable côté client.**
///
/// Toutes les propriétés sont `let` et le type est une `struct` : il n'existe
/// aucun chemin pour modifier un montant, un taux ou une échéance après
/// réception. `quoteHash` permet en plus au backend de constater qu'on lui
/// renvoie bien ce qu'il a émis.
///
/// Distinct de `TransferQuote` (Bloc 3), qui couvre l'envoi domestique : celui-ci
/// porte le change, la ventilation détaillée des frais et taxes, et le taux de
/// référence — ce que le chapitre 35 exige et qu'un devis domestique n'a pas.
public struct FinancialQuote: Codable, Sendable, Hashable, Identifiable {

    public let quoteID: String
    public var id: String { quoteID }
    public let quoteVersion: String

    public let sourceCurrency: String
    public let targetCurrency: String
    public let sourceAmount: Decimal
    public let targetAmount: Decimal

    /// Taux appliqué à ce client, marge comprise.
    public let exchangeRate: Decimal

    /// Taux de référence marché, **sans marge**.
    ///
    /// Séparé du taux client à dessein : c'est ce qui rend la marge visible.
    /// N'afficher que le taux client permet de présenter une marge élevée comme
    /// un taux — la transparence exigée au §17 tient à cette distinction.
    public let referenceRate: Decimal?

    public let fees: [QuoteFee]
    public let taxes: [QuoteTax]

    /// Total débité et total reçu, **calculés par le backend**.
    ///
    /// Ne jamais les recomposer depuis `sourceAmount + fees + taxes` : la règle
    /// de composition appartient au marché et au partenaire, pas au client.
    public let totalDebit: Decimal
    public let totalReceive: Decimal

    public let validUntil: Date
    public let serverTimestamp: Date

    /// Empreinte du devis, produite par le backend.
    public let quoteHash: String

    /// `false` ⇒ devis **indicatif**. Affichable, non exécutable.
    ///
    /// Un devis indicatif présenté comme exécutable ferait croire à un prix
    /// tenu. La distinction est portée par le contrat, pas par une convention.
    public let executable: Bool

    public init(
        quoteID: String, quoteVersion: String,
        sourceCurrency: String, targetCurrency: String,
        sourceAmount: Decimal, targetAmount: Decimal,
        exchangeRate: Decimal, referenceRate: Decimal? = nil,
        fees: [QuoteFee] = [], taxes: [QuoteTax] = [],
        totalDebit: Decimal, totalReceive: Decimal,
        validUntil: Date, serverTimestamp: Date,
        quoteHash: String, executable: Bool
    ) {
        self.quoteID = quoteID
        self.quoteVersion = quoteVersion
        self.sourceCurrency = sourceCurrency
        self.targetCurrency = targetCurrency
        self.sourceAmount = sourceAmount
        self.targetAmount = targetAmount
        self.exchangeRate = exchangeRate
        self.referenceRate = referenceRate
        self.fees = fees
        self.taxes = taxes
        self.totalDebit = totalDebit
        self.totalReceive = totalReceive
        self.validUntil = validUntil
        self.serverTimestamp = serverTimestamp
        self.quoteHash = quoteHash
        self.executable = executable
    }
}

public struct QuoteFee: Codable, Sendable, Hashable {
    /// Clé de libellé. Jamais une phrase.
    public let labelKey: String
    public let amount: Decimal
    public let currency: String
    public let kind: FeeKind

    public enum FeeKind: String, Codable, Sendable {
        case provider, platform, correspondent, delivery, other

        /// Une nature de frais inconnue devient `other` : elle reste **visible
        /// et comptée**. La masquer ferait apparaître un total supérieur à la
        /// somme des lignes affichées.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = FeeKind(rawValue: raw) ?? .other
        }
    }

    public init(labelKey: String, amount: Decimal, currency: String, kind: FeeKind) {
        self.labelKey = labelKey
        self.amount = amount
        self.currency = currency
        self.kind = kind
    }
}

public struct QuoteTax: Codable, Sendable, Hashable {
    public let labelKey: String
    public let amount: Decimal
    public let currency: String
    /// Taux appliqué, pour affichage. Le montant fait foi, pas ce taux.
    public let ratePercent: Decimal?

    public init(labelKey: String, amount: Decimal, currency: String, ratePercent: Decimal? = nil) {
        self.labelKey = labelKey
        self.amount = amount
        self.currency = currency
        self.ratePercent = ratePercent
    }
}

// MARK: - Gates §31

public extension FinancialQuote {

    func isExpired(asOf now: Date = Date()) -> Bool { now >= validUntil }

    func remainingValidity(asOf now: Date = Date()) -> TimeInterval {
        max(0, validUntil.timeIntervalSince(now))
    }

    /// `true` si ce devis peut être soumis à exécution.
    ///
    /// Les deux conditions comptent ensemble : un devis indicatif encore valide
    /// n'est pas exécutable, et un devis exécutable périmé ne l'est plus.
    func isExecutable(asOf now: Date = Date()) -> Bool {
        executable && !isExpired(asOf: now)
    }

    /// Marge appliquée, en points de pourcentage du taux de référence.
    ///
    /// `nil` quand le backend ne rend pas le taux de référence — et le client
    /// ne l'estime surtout pas : une marge inventée est une information fausse
    /// sur un sujet où l'utilisateur compare des offres.
    var marginPercent: Decimal? {
        guard let referenceRate, referenceRate > 0 else { return nil }
        return ((exchangeRate - referenceRate) / referenceRate) * 100
    }

    /// Empreinte locale des champs décisionnels, à comparer à `quoteHash`.
    ///
    /// **BACKEND CONTRACT REQUIRED** — la forme canonique doit être identique
    /// des deux côtés. Sert la gate §31 : détecter qu'un devis a été altéré
    /// entre réception et soumission.
    var computedHash: String {
        let canonical = [
            quoteID, quoteVersion,
            sourceCurrency, targetCurrency,
            "\(sourceAmount)", "\(targetAmount)", "\(exchangeRate)",
            "\(totalDebit)", "\(totalReceive)",
            fees.map { "\($0.labelKey):\($0.amount):\($0.currency)" }.sorted().joined(separator: ","),
            taxes.map { "\($0.labelKey):\($0.amount):\($0.currency)" }.sorted().joined(separator: ",")
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// `true` si le devis n'a pas été altéré depuis son émission.
    var isIntact: Bool { quoteHash == computedHash }
}

// MARK: - Divergence

/// Ce qui a changé entre deux devis. Gate §31.
public enum QuoteDivergence: String, Sendable, Equatable, CaseIterable {
    case sourceAmount, targetAmount, exchangeRate, fees, taxes
    case totalDebit, totalReceive, currency, executability, identity
}

public extension FinancialQuote {

    /// Compare deux devis champ décisionnel par champ décisionnel.
    ///
    /// `quoteVersion` et `serverTimestamp` sont exclus : un devis réédité pour
    /// des raisons techniques, à conditions identiques, ne doit pas forcer un
    /// nouvel accord de l'utilisateur.
    func divergences(from fresh: FinancialQuote) -> [QuoteDivergence] {
        var fields: [QuoteDivergence] = []
        if quoteID != fresh.quoteID { fields.append(.identity) }
        if sourceCurrency != fresh.sourceCurrency || targetCurrency != fresh.targetCurrency {
            fields.append(.currency)
        }
        if sourceAmount != fresh.sourceAmount { fields.append(.sourceAmount) }
        if targetAmount != fresh.targetAmount { fields.append(.targetAmount) }
        if exchangeRate != fresh.exchangeRate { fields.append(.exchangeRate) }
        if fees != fresh.fees { fields.append(.fees) }
        if taxes != fresh.taxes { fields.append(.taxes) }
        if totalDebit != fresh.totalDebit { fields.append(.totalDebit) }
        if totalReceive != fresh.totalReceive { fields.append(.totalReceive) }
        if executable != fresh.executable { fields.append(.executability) }
        return fields
    }
}
