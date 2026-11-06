//
//  FinancialAuditEmitting.swift
//  CoreKit
//
//  Bloc 9, §21-22 — émission des faits d'audit vers l'autorité qui les chaîne.
//

import Foundation

/// Ce que l'autorité d'audit renvoie après acceptation.
///
/// Le serveur, et lui seul, fixe l'horodatage et le maillon de chaîne. Un client
/// qui les fabriquerait produirait une preuve qu'il contrôle — c'est-à-dire pas
/// une preuve.
public struct AuditAcknowledgement: Sendable, Equatable {

    /// Identifiant de l'événement tel qu'accepté.
    public let eventID: String

    /// Horodatage **serveur**, seul faisant foi.
    public let acceptedAt: Date

    /// Empreinte de l'événement précédent dans la chaîne.
    public let previousHash: String

    /// Empreinte de cet événement, maillon suivant.
    public let hash: String

    /// Rang dans la chaîne. Un trou ici est un événement manquant.
    public let sequence: Int64

    public init(
        eventID: String, acceptedAt: Date,
        previousHash: String, hash: String, sequence: Int64
    ) {
        self.eventID = eventID
        self.acceptedAt = acceptedAt
        self.previousHash = previousHash
        self.hash = hash
        self.sequence = sequence
    }
}

/// Échec d'émission.
public enum AuditEmissionError: Error, Sendable, Equatable {

    /// L'autorité est injoignable. **L'événement n'est pas perdu** : il doit
    /// être remis en file, sinon un incident réseau efface sa propre trace.
    case unreachable

    /// L'événement porte une clé interdite. Refus délibéré côté serveur.
    case rejectedContent(reason: String)

    /// Chaîne rompue : l'événement reçu ne suit pas le dernier maillon connu.
    case chainMismatch(expectedPrevious: String)
}

/// Remet un fait d'audit à l'autorité qui le chaîne et l'horodate.
///
/// **Le mobile n'est jamais la source unique de preuve** (§22). Il constate et
/// transmet ; l'ordre, l'horodatage et l'intégrité appartiennent au serveur.
public protocol FinancialAuditEmitting: Sendable {

    /// Remet l'événement. L'accusé porte ce que seul le serveur peut établir.
    func emit(_ event: FinancialAuditEvent) async -> Result<AuditAcknowledgement, AuditEmissionError>
}

/// N'émet rien et le dit.
///
/// Défaut explicite : rend visible dans le graphe de dépendances qu'aucune
/// autorité d'audit n'est branchée, plutôt que de laisser les appels réussir
/// dans le vide.
public struct UnavailableAuditEmitter: FinancialAuditEmitting {
    public init() {}
    public func emit(_ event: FinancialAuditEvent) async -> Result<AuditAcknowledgement, AuditEmissionError> {
        .failure(.unreachable)
    }
}
