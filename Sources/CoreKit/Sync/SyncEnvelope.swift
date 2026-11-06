//
//  SyncEnvelope.swift
//  CoreKit
//
//  Enveloppe et contrats d'API de synchronisation — Bloc 8, §24 et §25.
//
//  **BACKEND CONTRACT REQUIRED** — les neuf routes ci-dessous ne sont pas
//  négociées. Ce fichier fixe ce que le client exige d'elles.
//

import Foundation

// MARK: - Métadonnées de réponse (§24)

/// Ce que **toute** réponse doit porter.
///
/// Le §24 en fait une obligation sans exception, et chacun des cinq champs
/// paie sa place : sans `serverTime` le client date avec son horloge, qui
/// dérive ; sans `objectVersion` il ne peut pas détecter qu'il écrase du plus
/// récent ; sans `correlationID` une trace s'arrête à la frontière réseau.
public struct ResponseMetadata: Codable, Sendable, Hashable {

    public let requestID: String
    public let correlationID: String

    /// Horloge du serveur. **Fait autorité sur l'horloge locale.**
    ///
    /// Une horloge d'appareil peut être fausse de plusieurs heures, par dérive
    /// ou parce que l'utilisateur l'a changée. Dater une expiration financière
    /// avec elle rendrait un devis périmé valide.
    public let serverTime: Date

    public let schemaVersion: Int

    /// Version de l'objet rendu. `nil` pour une collection.
    public let objectVersion: Int64?

    public init(requestID: String, correlationID: String, serverTime: Date,
                schemaVersion: Int, objectVersion: Int64? = nil) {
        self.requestID = requestID
        self.correlationID = correlationID
        self.serverTime = serverTime
        self.schemaVersion = schemaVersion
        self.objectVersion = objectVersion
    }

    /// La version de schéma la plus élevée que ce client sait interpréter.
    public static let supportedSchemaVersion = 1

    /// Le client peut-il traiter cette réponse ?
    ///
    /// Un schéma **plus récent** que celui compris n'est pas traité : appliquer
    /// une charge dont on ignore les champs revient à en perdre en silence. Un
    /// schéma plus ancien reste lisible.
    public var isInterpretable: Bool {
        schemaVersion <= Self.supportedSchemaVersion
    }

    /// Décalage entre l'horloge locale et celle du serveur.
    ///
    /// À journaliser : une dérive importante explique des expirations
    /// inattendues, et se diagnostique mal autrement.
    public func clockSkew(localNow: Date = Date()) -> TimeInterval {
        localNow.timeIntervalSince(serverTime)
    }
}

// MARK: - Enveloppe (§25)

/// Une page de résultats de synchronisation.
public struct SyncEnvelope<Item: Codable & Sendable>: Codable, Sendable {

    public let metadata: ResponseMetadata

    /// Curseur de la page **suivante**. `nil` ⇒ fin du flux.
    public let cursor: String?

    /// Il reste des pages.
    public let hasMore: Bool

    public let items: [Item]

    public init(metadata: ResponseMetadata, cursor: String?,
                hasMore: Bool, items: [Item]) {
        self.metadata = metadata
        self.cursor = cursor
        self.hasMore = hasMore
        self.items = items
    }

    /// Incohérence entre `hasMore` et `cursor`.
    ///
    /// `hasMore == true` sans curseur est une page qu'on ne peut pas suivre :
    /// le client boucle ou s'arrête, et les deux sont faux. Mieux vaut le
    /// détecter que le subir.
    public var isSelfConsistent: Bool {
        hasMore ? cursor != nil : true
    }
}

// MARK: - Routes (§24)

/// Les neuf routes du §24, et ce que le client exige de chacune.
///
/// Énumérées dans le code plutôt que laissées à des chaînes dispersées : une
/// route qui exige une clé d'idempotence et qu'on appelle sans elle est un
/// doublon en puissance, et cette propriété doit être lisible au même endroit
/// que le chemin.
public enum SyncEndpoint: Sendable, Hashable, CaseIterable {

    case sendMessage
    case chatSync
    case conversation
    case financialObject
    case financialObjectStatus
    case sessions
    case revokeSession
    case reconcile
    case uploads

    public var path: String {
        switch self {
        case .sendMessage:           return "/v1/chat/messages"
        case .chatSync:              return "/v1/chat/sync"
        case .conversation:          return "/v1/chat/conversations/{id}"
        case .financialObject:       return "/v1/financial-objects/{id}"
        case .financialObjectStatus: return "/v1/financial-objects/{id}/status"
        case .sessions:              return "/v1/sessions"
        case .revokeSession:         return "/v1/sessions/{id}"
        case .reconcile:             return "/v1/sync/reconcile"
        case .uploads:               return "/v1/uploads"
        }
    }

    public var method: String {
        switch self {
        case .sendMessage, .reconcile, .uploads: return "POST"
        case .revokeSession:                     return "DELETE"
        default:                                 return "GET"
        }
    }

    /// Écrit-elle ?
    public var isMutation: Bool { method != "GET" }

    /// Exige une clé d'idempotence.
    ///
    /// Toute mutation, sans exception. `revokeSession` y compris : révoquer
    /// deux fois doit valoir révoquer une fois, sinon un retry sur une réponse
    /// perdue produit une seconde révocation qui échoue et alarme pour rien.
    public var requiresIdempotencyKey: Bool { isMutation }

    /// Se pagine par curseur.
    public var isPaginated: Bool {
        self == .chatSync || self == .sessions
    }

    /// Peut être interrogée pour lever une issue inconnue (§10).
    ///
    /// C'est la route qu'on appelle **au lieu** de rejouer une mutation dont on
    /// n'a pas eu la réponse.
    public var isRequerySafe: Bool {
        self == .financialObjectStatus || self == .financialObject
    }
}
