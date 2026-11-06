//
//  EventEnvelope.swift
//  CoreKit
//
//  Événements financiers typés — Bloc 2 ch. 14, Bloc 4 ch. 32 (GAP-07, GAP-14).
//

import Foundation

/// Enveloppe d'un événement financier.
///
/// **Aucun événement n'écrit un statut.** Un événement déclenche une lecture ou
/// enrichit l'historique — jamais l'état courant. Cette règle vient du Bloc 1 et
/// ne bouge pas : un statut transporté par un canal temps réel arrive sans
/// garantie d'ordre, sans signature vérifiable et sans corrélation à la requête
/// qui l'a produit.
public struct EventEnvelope: Codable, Sendable, Hashable, Identifiable {

    /// Identité de l'événement. **Clé de déduplication** : un même `eventId`
    /// livré deux fois est le même fait, pas deux.
    public let eventID: String
    public var id: String { eventID }

    public let eventType: String
    public let schemaVersion: SchemaVersion

    public let aggregateID: String
    /// Rang dans la séquence de cet agrégat. **Strictement croissant.**
    /// C'est ce qui rend un trou détectable.
    public let aggregateVersion: Int

    public let occurredAt: Date
    public let producer: String

    public let correlationID: CorrelationId
    /// Ce qui a **causé** cet événement.
    ///
    /// Distinct de la corrélation : celle-ci relie des appels entre eux, la
    /// causation dit lequel a provoqué lequel. Lors d'un incident, c'est la
    /// différence entre « ces dix requêtes partagent une corrélation » et
    /// « cette confirmation vient de ce rejeu ».
    public let causationID: String?

    public init(
        eventID: String, eventType: String, schemaVersion: SchemaVersion,
        aggregateID: String, aggregateVersion: Int, occurredAt: Date,
        producer: String, correlationID: CorrelationId, causationID: String? = nil
    ) {
        self.eventID = eventID
        self.eventType = eventType
        self.schemaVersion = schemaVersion
        self.aggregateID = aggregateID
        self.aggregateVersion = aggregateVersion
        self.occurredAt = occurredAt
        self.producer = producer
        self.correlationID = correlationID
        self.causationID = causationID
    }
}

/// Version de schéma d'un contrat, en deux parties.
public struct SchemaVersion: Codable, Sendable, Hashable, Comparable {

    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.major == rhs.major ? lhs.minor < rhs.minor : lhs.major < rhs.major
    }

    /// `true` si ce client sait lire cette version.
    ///
    /// Un `major` supérieur n'est pas lisible : le client ne sait pas ce qu'il
    /// lirait. Un `minor` supérieur l'est, en ignorant l'inconnu — c'est ce qui
    /// permet au backend d'ajouter un champ sans casser les clients déployés.
    public func isReadable(by supported: SchemaVersion) -> Bool {
        major <= supported.major
    }
}

// MARK: - Inbox

/// Ce que l'inbox conclut d'un événement entrant.
public enum InboxVerdict: Sendable, Equatable {

    /// Nouveau et dans l'ordre : à traiter.
    case accept

    /// Déjà vu. **Ignoré sans erreur** : un webhook rejoué est un fait normal
    /// d'un transport au-moins-une-fois, pas un incident.
    case duplicate

    /// Version déjà dépassée. Le traiter réappliquerait un état ancien.
    case stale(current: Int)

    /// **Trou détecté.** Des versions manquent entre la dernière connue et
    /// celle-ci. L'événement n'est pas appliqué à l'aveugle : l'agrégat est
    /// resynchronisé, parce qu'on ignore ce que les versions manquantes disaient.
    case gap(missingFrom: Int, missingTo: Int)

    /// Schéma illisible par ce client.
    case unsupportedSchema
}

/// Décide du sort de chaque événement entrant, par agrégat.
///
/// **Pure et testable.** La logique de déduplication et de détection de trou ne
/// dépend d'aucun stockage : elle prend l'état connu et l'événement, et rend un
/// verdict. Le stockage est la responsabilité de l'appelant.
public struct EventInboxPolicy: Sendable {

    /// Version de schéma que ce binaire sait lire.
    public let supportedSchema: SchemaVersion

    public init(supportedSchema: SchemaVersion = SchemaVersion(major: 1, minor: 0)) {
        self.supportedSchema = supportedSchema
    }

    /// - Parameter lastAppliedVersion: dernière version appliquée pour cet
    ///   agrégat, `nil` si aucun événement n'a encore été vu.
    /// - Parameter seenEventIDs: identifiants déjà traités.
    public func verdict(
        for event: EventEnvelope,
        lastAppliedVersion: Int?,
        seenEventIDs: Set<String>
    ) -> InboxVerdict {

        // La déduplication passe avant tout : un rejeu d'un événement déjà
        // appliqué ne doit surtout pas être compté comme un trou.
        if seenEventIDs.contains(event.eventID) { return .duplicate }

        guard event.schemaVersion.isReadable(by: supportedSchema) else {
            return .unsupportedSchema
        }

        guard let last = lastAppliedVersion else {
            // Premier événement connu pour cet agrégat. On ne peut pas savoir
            // s'il en manque avant : ce n'est pas un trou, c'est un début.
            return .accept
        }

        if event.aggregateVersion <= last { return .stale(current: last) }

        if event.aggregateVersion > last + 1 {
            return .gap(missingFrom: last + 1, missingTo: event.aggregateVersion - 1)
        }

        return .accept
    }
}
