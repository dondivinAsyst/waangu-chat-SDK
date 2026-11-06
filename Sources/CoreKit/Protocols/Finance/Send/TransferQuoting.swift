//
//  TransferQuoting.swift
//  CoreKit
//
//  Devis de transfert — Bloc 3, chapitre 18.2.
//
//  **BACKEND CONTRACT REQUIRED** — `POST /v1/transfers/quote`.
//

import Foundation

/// Produit et rafraîchit les devis de transfert.
///
/// Le devis est la seule source des montants, frais, taxes et taux. Le client
/// les affiche ; il n'en recalcule aucun. Un `amount * 0.02` écrit ici
/// divergerait du ledger au premier changement de barème, et l'utilisateur
/// verrait un total qui n'est pas celui qu'on lui débitera.
public protocol TransferQuoting: Sendable {

    func quote(for draft: TransferDraft) async -> Result<TransferQuote, FinanceError>

    /// Relit le devis juste avant l'exécution.
    ///
    /// Distinct de `quote` à dessein : c'est l'appel des étapes 1 à 4 de la
    /// séquence de confirmation, le seul moment où un cache est exactement ce
    /// qu'il ne faut pas lire.
    func refreshQuote(_ quote: TransferQuote) async -> Result<TransferQuote, FinanceError>
}

// MARK: - Brouillon

public struct TransferDraft: Sendable, Hashable, Codable {
    public let recipientID: String
    public let amount: Decimal
    public let currency: String
    public let conversationID: String?
    public let note: String?

    /// Source de financement choisie. `nil` ⇒ le backend prend celle par défaut.
    ///
    /// Sans ce champ, un sélecteur de source ne déciderait de rien : l'écran
    /// laisserait choisir un compte, et le débit partirait d'un autre.
    public let sourceID: String?

    public init(
        recipientID: String,
        amount: Decimal,
        currency: String,
        conversationID: String? = nil,
        note: String? = nil,
        sourceID: String? = nil
    ) {
        self.recipientID = recipientID
        self.amount = amount
        self.currency = currency
        self.conversationID = conversationID
        self.note = note
        self.sourceID = sourceID
    }
}

// MARK: - Devis

/// Ce que le backend facture pour ce transfert, et jusqu'à quand.
public struct TransferQuote: Sendable, Hashable, Codable {

    public let reference: FinancialReference

    public let amount: Decimal
    public let currency: String

    /// Frais rendus par le backend. `nil` ⇒ le backend ne les a pas fournis,
    /// ce qui n'est **pas** la même chose que zéro frais.
    public let feeAmount: Decimal?
    public let feeCurrency: String?

    public let taxAmount: Decimal?
    public let exchangeRate: Decimal?

    /// Total à débiter, **calculé par le backend**.
    ///
    /// Ne jamais le recomposer à partir de `amount + fee + tax` : la règle de
    /// composition appartient au marché, pas au client, et une devise de frais
    /// différente rendrait l'addition fausse en silence.
    public let totalAmount: Decimal?
    public let totalCurrency: String?

    public let recipientVerification: VerificationStatus
    public let complianceState: ComplianceState

    /// Horloge serveur. Une horloge client permettrait de rajeunir un devis
    /// périmé en changeant l'heure de l'appareil.
    public let issuedAt: Date

    /// **Échéance du devis.**
    ///
    /// Le défaut que le Bloc 1 a laissé ouvert : `PreparedPaymentIntent.expiresAt`
    /// était `nil` en dur, donc `isExpired()` ne pouvait jamais se déclencher.
    /// Ici le champ est **non optionnel** — un devis sans échéance n'est pas un
    /// devis, c'est une promesse que personne ne tient.
    public let expiresAt: Date

    public init(
        reference: FinancialReference,
        amount: Decimal,
        currency: String,
        feeAmount: Decimal? = nil,
        feeCurrency: String? = nil,
        taxAmount: Decimal? = nil,
        exchangeRate: Decimal? = nil,
        totalAmount: Decimal? = nil,
        totalCurrency: String? = nil,
        recipientVerification: VerificationStatus,
        complianceState: ComplianceState,
        issuedAt: Date,
        expiresAt: Date
    ) {
        self.reference = reference
        self.amount = amount
        self.currency = currency
        self.feeAmount = feeAmount
        self.feeCurrency = feeCurrency
        self.taxAmount = taxAmount
        self.exchangeRate = exchangeRate
        self.totalAmount = totalAmount
        self.totalCurrency = totalCurrency
        self.recipientVerification = recipientVerification
        self.complianceState = complianceState
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }
}

public extension TransferQuote {

    /// `true` si le devis est périmé.
    ///
    /// Contrairement au Bloc 1, ce contrôle **peut** se déclencher : `expiresAt`
    /// est obligatoire.
    func isExpired(asOf now: Date = Date()) -> Bool { now >= expiresAt }

    /// Temps restant, pour l'afficher.
    func remainingValidity(asOf now: Date = Date()) -> TimeInterval {
        max(0, expiresAt.timeIntervalSince(now))
    }

    /// L'aperçu exact soumis à l'accord de l'utilisateur.
    ///
    /// C'est ce que la confirmation comparera à un devis rafraîchi. Tout ce qui
    /// entre ici est un champ décisionnel ; tout ce qui n'y entre pas ne peut
    /// pas invalider un accord.
    func snapshot(recipientID: String) -> ConfirmationSnapshot {
        ConfirmationSnapshot(
            reference: reference,
            amount: amount,
            currency: currency,
            feeAmount: feeAmount,
            feeCurrency: feeCurrency,
            exchangeRate: exchangeRate,
            recipientID: recipientID,
            recipientVerification: recipientVerification,
            complianceState: complianceState,
            capturedAt: issuedAt
        )
    }
}
