//
//  Migrationmanager.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : CoreKit                                            │
// │  FICHIER : Database/QuerySpec.swift                          │
// │                                                              │
// │  Représentation d'une requête indépendante de tout engine.   │
// │  StorageKit traduit QuerySpec en #Predicate, NSPredicate,    │
// │  clause WHERE SQL, ou query Realm selon l'engine actif.      │
// └──────────────────────────────────────────────────────────────┘

import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: QuerySpec
// ─────────────────────────────────────────────────────────────

/// Spécification d'une requête de lecture.
/// Construite par les features, traduite par StorageKit.
///
/// Exemple :
/// ```swift
/// var query = QuerySpec()
/// query.sort    = [SortSpec("timestamp", ascending: false)]
/// query.limit   = 50
/// ```
public struct QuerySpec: Sendable {
    public var filter: FilterSpec?
    public var sort: [SortSpec]
    public var limit: Int?
    public var offset: Int?

    public init(
        filter: FilterSpec? = nil,
        sort: [SortSpec] = [],
        limit: Int? = nil,
        offset: Int? = nil
    ) {
        self.filter = filter
        self.sort   = sort
        self.limit  = limit
        self.offset = offset
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: FilterSpec
// ─────────────────────────────────────────────────────────────

/// Filtre sous forme de format string + arguments typés.
/// Intentionnellement simple : les cas complexes passent par
/// plusieurs appels fetch côté feature, pas par un DSL de requête
/// que StorageKit devrait traduire dans 4 technologies différentes.
///
/// Format identique à NSPredicate — StorageKit adapte pour chaque engine :
///   CoreData  → NSPredicate(format:arguments:)
///   SwiftData → traduit manuellement en #Predicate
///   SQLite    → traduit en clause WHERE paramétrisée
///   Realm     → traduit en NSPredicate Realm
public struct FilterSpec: Sendable {
    public let format: String
    public let arguments: [AnyStorableArgument]

    public init(_ format: String, _ arguments: AnyStorableArgument...) {
        self.format    = format
        self.arguments = arguments
    }
}

/// Valeur scalaire utilisable dans un FilterSpec.
/// Enum fermée : on maîtrise ce qui peut entrer dans un filtre.
public enum AnyStorableArgument: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case uuid(UUID)
    case date(Date)
}

// ─────────────────────────────────────────────────────────────
// MARK: SortSpec
// ─────────────────────────────────────────────────────────────

/// Critère de tri : nom du champ + direction.
/// Le nom de champ correspond à la propriété Swift de l'entité.
public struct SortSpec: Sendable {
    public let keyPath: String
    public let ascending: Bool

    public init(_ keyPath: String, ascending: Bool = true) {
        self.keyPath   = keyPath
        self.ascending = ascending
    }
}
