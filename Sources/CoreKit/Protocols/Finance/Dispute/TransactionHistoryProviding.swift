//
//  TransactionHistoryProviding.swift
//  CoreKit
//
//  Relevé des opérations du compte.
//

import Foundation

// MARK: - Entrée

/// Une opération telle qu'elle apparaît au relevé.
///
/// **Rendue par le backend, jamais agrégée ici.** Le client possède les
/// opérations qu'il a lui-même émises, et rien d'autre : ni les débits reçus,
/// ni les frais, ni les reprises. Un relevé composé localement diverge de la
/// comptabilité dès la première opération passée depuis un autre appareil, et
/// l'écart ne se voit pas — il s'accumule.
public struct TransactionHistoryEntry: Identifiable, Sendable, Hashable {

    /// Sens du mouvement, du point de vue du titulaire du compte.
    ///
    /// Porté explicitement plutôt que déduit du signe du montant : ``Money``
    /// stocke des unités mineures signées, et un rail qui rendrait un débit en
    /// positif ferait afficher un crédit. Le sens est une donnée, pas un calcul.
    public enum Direction: String, Codable, Sendable {
        case debit
        case credit
    }

    public let id: String

    /// L'objet financier sous-jacent, quand il en existe un.
    ///
    /// `nil` pour les écritures qui n'ont pas d'objet propre — frais, ajustement
    /// comptable. La ligne reste affichable ; seul son détail est hors de portée.
    public let reference: FinancialReference?

    /// Nature du parcours qui a produit l'opération, quand elle est connue.
    public let kind: FinanceEntryKind?

    /// Libellé rendu par le backend.
    ///
    /// Non traduit côté client : c'est un nom de contrepartie ou de facturier,
    /// pas une clé. Le traduire reviendrait à réécrire le nom du bénéficiaire.
    public let label: String

    public let amount: Money
    public let direction: Direction

    /// Statut réel, y compris non final.
    ///
    /// Une ligne en attente s'affiche **en attente**. La reléguer hors du relevé
    /// jusqu'à sa finalité ferait disparaître un débit déjà passé.
    public let status: PaymentStatus

    public let occurredAt: Date

    public init(
        id: String,
        reference: FinancialReference? = nil,
        kind: FinanceEntryKind? = nil,
        label: String,
        amount: Money,
        direction: Direction,
        status: PaymentStatus,
        occurredAt: Date
    ) {
        self.id = id
        self.reference = reference
        self.kind = kind
        self.label = label
        self.amount = amount
        self.direction = direction
        self.status = status
        self.occurredAt = occurredAt
    }
}

// MARK: - Page

/// Une tranche de relevé.
///
/// Curseur opaque plutôt que numéro de page : le relevé s'allonge par le haut
/// pendant qu'on le parcourt, et une pagination par index saute des lignes ou
/// en répète.
public struct TransactionHistoryPage: Sendable {

    public let entries: [TransactionHistoryEntry]

    /// `nil` ⇒ fin du relevé. À distinguer d'une page vide, qui peut précéder
    /// d'autres pages sur un intervalle sans opération.
    public let nextCursor: String?

    public init(entries: [TransactionHistoryEntry], nextCursor: String?) {
        self.entries = entries
        self.nextCursor = nextCursor
    }
}

// MARK: - Contrat

/// Lecture du relevé des opérations.
///
/// **BACKEND CONTRACT REQUIRED** — `GET /v1/accounts/{id}/transactions`.
///
/// En lecture seule : rien de ce qui est ici ne déplace d'argent. Le relevé sert
/// à constater, et la reprise d'une opération échouée passe par le parcours qui
/// l'a produite — pas par une ligne de liste.
public protocol TransactionHistoryProviding: Sendable {

    /// - Parameters:
    ///   - cursor: `nil` pour la première page.
    ///   - limit: nombre de lignes souhaité. Le backend peut en rendre moins.
    func history(
        cursor: String?,
        limit: Int
    ) async -> Result<TransactionHistoryPage, FinanceError>
}
