// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : CoreKit                                            │
// │  FICHIER : Database/SearchableDatabaseProtocol.swift         │
// │                                                              │
// │  Extension de DatabaseRepositoryProtocol pour la recherche   │
// │  full-text et les jointures relationnelles.                  │
// │                                                              │
// │  Implémenté par DatabaseStore (StorageKit) quand l'engine    │
// │  sous-jacent supporte ces capacités.                         │
// │  Les features n'importent que CoreKit.                       │
// │                                                              │
// │  NOTE : SQLiteStorable a été supprimé.                       │
// │  Les hints de performance (indexedFields, searchableFields,  │
// │  foreignKeys) sont directement dans Storable.                │
// │  Aucun type dans CoreKit ne mentionne une technologie.       │
// └──────────────────────────────────────────────────────────────┘

import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: SearchableDatabaseProtocol
// ─────────────────────────────────────────────────────────────

public protocol SearchableDatabaseProtocol: DatabaseRepositoryProtocol {

    // ── Full-text search ──────────────────────────────────────

    /// Recherche full-text sur plusieurs types d'entités.
    /// L'engine décide comment l'implémenter :
    ///   SQLiteEngine   → FTS5, résultat en < 2ms sur 1M lignes
    ///   CoreDataEngine → non supporté, throw engineUnavailable
    ///   InMemoryEngine → filtre en mémoire (tests uniquement)
    func search(
        keyword:   String,
        in types:  [any Storable.Type],
        namespace: String,
        limit:     Int
    ) async throws -> SearchResults

    // ── Relations ─────────────────────────────────────────────

    /// Fetch une entité + sa relation 1-1.
    /// L'engine fait deux requêtes filtrées sur IDs — pas de
    /// chargement complet en mémoire.
    func fetchJoined<Root, Related>(
        _ root:     Root.Type,
        joinedTo:   Related.Type,
        on keyPath: KeyPath<Root, Related.ID?>,
        rootQuery:  QuerySpec?
    ) async throws -> [(root: Root, related: Related?)]
    where Root: Storable, Related: Storable

    /// Fetch une entité + ses enfants 1-N.
    /// Utilise la colonne indexée déclarée dans foreignKeys.
    func fetchWithChildren<Root, Child>(
        _ root:     Root.Type,
        children:   Child.Type,
        on keyPath: KeyPath<Child, Root.ID>,
        rootQuery:  QuerySpec?
    ) async throws -> [(root: Root, children: [Child])]
    where Root: Storable, Child: Storable

    // ── Requêtes custom ───────────────────────────────────────
    // Compromis assumé : la feature qui utilise ces méthodes
    // accepte de ne pas être portable vers CoreData/Realm.
    // Réservé aux cas que QuerySpec ne couvre pas :
    //   GROUP BY, HAVING, sous-requêtes, agrégations.

    /// Exécute une requête custom et décode les résultats
    /// depuis json_payload. Les colonnes retournées DOIVENT
    /// inclure json_payload pour que le décodage fonctionne.
    func fetchRaw<T: Storable>(
        _ type:     T.Type,
        rawQuery:   String,
        arguments:  [AnyStorableArgument],
        namespace:  String
    ) async throws -> [T]

    /// Exécute une requête d'agrégation et retourne les rows bruts.
    /// Utile pour COUNT, SUM, AVG groupé par colonne.
    func fetchAggregate(
        rawQuery:   String,
        arguments:  [AnyStorableArgument],
        namespace:  String
    ) async throws -> [[String: Any]]
}

// ─────────────────────────────────────────────────────────────
// MARK: Résultats de recherche
// ─────────────────────────────────────────────────────────────

public struct SearchResults: Sendable {

    public let groups:     [String: [SearchHit]]
    public let totalCount: Int
    public let keyword:    String
    public let durationMs: Int

    public init(
        groups:     [String: [SearchHit]],
        keyword:    String,
        durationMs: Int
    ) {
        self.groups     = groups
        self.totalCount = groups.values.reduce(0) { $0 + $1.count }
        self.keyword    = keyword
        self.durationMs = durationMs
    }

    public func hits<T: Storable>(for type: T.Type) -> [SearchHit] {
        groups["\(type)"] ?? []
    }

    public var isEmpty: Bool { totalCount == 0 }
}

public struct SearchHit: Sendable, Identifiable {
    public let id:         String
    public let entityType: String
    public let snippet:    String
    public let rank:       Double
    public let rawData:    Data

    public init(id: String, entityType: String, snippet: String, rank: Double, rawData: Data) {
        self.id         = id
        self.entityType = entityType
        self.snippet    = snippet
        self.rank       = rank
        self.rawData    = rawData
    }

    public func decode<T: Storable>(as type: T.Type) -> T? {
        try? JSONDecoder().decode(type, from: rawData)
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: StorableForeignKey
// ─────────────────────────────────────────────────────────────
// Décrit une relation vers une autre entité.
// Agnostique — chaque engine l'interprète à sa façon :
//   SQLiteEngine   → FOREIGN KEY + ON DELETE CASCADE
//   CoreDataEngine → pourrait créer une NSRelationshipDescription
//   InMemoryEngine → ignoré

public struct StorableForeignKey: Sendable {
    public let column:          String
    public let referencesTable: String
    public let onDelete:        ForeignKeyAction

    public init(
        _ column:         String,
        references table: String,
        onDelete:         ForeignKeyAction = .cascade
    ) {
        self.column          = column
        self.referencesTable = table
        self.onDelete        = onDelete
    }
}

public enum ForeignKeyAction: Sendable {
    case cascade
    case setNull
    case restrict
    case noAction
}
