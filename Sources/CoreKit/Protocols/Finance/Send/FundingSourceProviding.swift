//
//  FundingSourceProviding.swift
//  CoreKit
//
//  D'où part l'argent.
//

import Foundation

/// Un compte, une carte ou un porte-monnaie utilisable pour payer.
///
/// **Le client choisit, le backend décide.** Une source marquée utilisable peut
/// être refusée à l'exécution — plafond atteint entre-temps, carte expirée dans
/// l'intervalle. Le drapeau sert à ne pas proposer l'évidemment impossible, pas
/// à garantir le possible.
public struct FundingSource: Identifiable, Sendable, Hashable {

    public enum Kind: String, Codable, Sendable {
        case wallet
        case card
        case bank
        case mobileMoney
    }

    public let id: String

    /// Nom rendu par le backend — « Compte principal », « Visa … 4242 ».
    public let name: String

    public let kind: Kind

    /// Fin d'identifiant, quand il y en a un. `nil` pour un porte-monnaie.
    ///
    /// Tronqué **par le backend**. Un numéro complet n'a aucune raison
    /// d'atteindre le client pour être masqué à l'affichage.
    public let maskedIdentifier: String?

    /// Solde disponible. `nil` quand la source n'en expose pas — une carte
    /// bancaire, typiquement. À distinguer d'un solde nul.
    public let availableBalance: Decimal?

    public let currency: String

    /// Source proposée par défaut. Le backend en désigne au plus une.
    public let isDefault: Bool

    /// `false` ⇒ la source s'affiche **grisée avec son motif**, pas masquée.
    /// Une source disparue se cherche ; une source expliquée se comprend.
    public let isUsable: Bool

    /// Clé de traduction du motif d'indisponibilité.
    public let unavailableReasonKey: String?

    public init(
        id: String,
        name: String,
        kind: Kind,
        maskedIdentifier: String? = nil,
        availableBalance: Decimal? = nil,
        currency: String,
        isDefault: Bool = false,
        isUsable: Bool = true,
        unavailableReasonKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.maskedIdentifier = maskedIdentifier
        self.availableBalance = availableBalance
        self.currency = currency
        self.isDefault = isDefault
        self.isUsable = isUsable
        self.unavailableReasonKey = unavailableReasonKey
    }
}

/// Lecture des sources de paiement disponibles.
///
/// **BACKEND CONTRACT REQUIRED** — `GET /v1/funding-sources?currency=…`.
///
/// Filtré par devise à la source : proposer un compte en CAD pour un envoi en
/// BIF obligerait le client à décider d'une conversion, ce qu'il n'a ni le taux
/// ni l'autorité pour faire.
public protocol FundingSourceProviding: Sendable {
    func sources(for currency: String) async -> Result<[FundingSource], FinanceError>
}
