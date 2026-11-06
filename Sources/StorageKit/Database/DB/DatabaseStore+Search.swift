//
//  DatabaseStore+Search.swift
//  AppModules
//
//  Created by Asyst on 5/18/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/DatabaseStore+Search.swift               │
// │                                                              │
// │  Extension de DatabaseStore qui implémente                   │
// │  SearchableDatabaseProtocol (CoreKit) en déléguant à        │
// │  SearchCapableEngine (interne StorageKit).                   │
// │                                                              │
// │  DatabaseStore vérifie si son engine est SearchCapableEngine.│
// │  Si oui → délègue. Sinon → throw engineUnavailable.         │
// │                                                              │
// │  Les features reçoivent SearchableDatabaseProtocol via      │
// │  injection. Elles ne savent pas que c'est un DatabaseStore  │
// │  ni que l'engine est SQLiteEngine.                          │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseStore + SearchableDatabaseProtocol
// ─────────────────────────────────────────────────────────────

extension DatabaseStore: SearchableDatabaseProtocol {

    // ─────────────────────────────────────────────────────────
    // MARK: Full-text search
    // ─────────────────────────────────────────────────────────

    public func search(
        keyword:   String,
        in types:  [any Storable.Type],
        namespace: String,
        limit:     Int
    ) async throws -> SearchResults {
        guard let searchEngine = engine as? SearchCapableEngine else {
            throw DatabaseError.engineUnavailable(
                reason: "L'engine actif ne supporte pas le full-text search. Utiliser .sqlite."
            )
        }
        return try await searchEngine.engineSearch(
            keyword:   keyword,
            in:        types,
            namespace: namespace,
            limit:     limit
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: fetchJoined — relation 1-1
    // ─────────────────────────────────────────────────────────

    public func fetchJoined<Root, Related>(
        _ root:     Root.Type,
        joinedTo:   Related.Type,
        on keyPath: KeyPath<Root, Related.ID?>,
        rootQuery:  QuerySpec?
    ) async throws -> [(root: Root, related: Related?)]
    where Root: Storable, Related: Storable {
        guard let searchEngine = engine as? SearchCapableEngine else {
            throw DatabaseError.engineUnavailable(
                reason: "L'engine actif ne supporte pas les jointures. Utiliser .sqlite."
            )
        }
        return try await searchEngine.engineFetchJoined(
            root,
            joinedTo:  Related.self,
            on:        keyPath,
            rootQuery: rootQuery,
            namespace: Root.namespace
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: fetchWithChildren — relation 1-N
    // ─────────────────────────────────────────────────────────

    public func fetchWithChildren<Root, Child>(
        _ root:     Root.Type,
        children:   Child.Type,
        on keyPath: KeyPath<Child, Root.ID>,
        rootQuery:  QuerySpec?
    ) async throws -> [(root: Root, children: [Child])]
    where Root: Storable, Child: Storable {
        guard let searchEngine = engine as? SearchCapableEngine else {
            throw DatabaseError.engineUnavailable(
                reason: "L'engine actif ne supporte pas les relations 1-N. Utiliser .sqlite."
            )
        }
        return try await searchEngine.engineFetchWithChildren(
            root,
            children:  Child.self,
            on:        keyPath,
            rootQuery: rootQuery,
            namespace: Root.namespace
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: fetchRaw — requête custom
    // ─────────────────────────────────────────────────────────

    public func fetchRaw<T: Storable>(
        _ type:    T.Type,
        rawQuery:  String,
        arguments: [AnyStorableArgument],
        namespace: String
    ) async throws -> [T] {
        guard let searchEngine = engine as? SearchCapableEngine else {
            throw DatabaseError.engineUnavailable(
                reason: "fetchRaw n'est supporté que par SQLiteEngine."
            )
        }
        return try await searchEngine.engineFetchRaw(
            type,
            rawQuery:  rawQuery,
            arguments: arguments,
            namespace: namespace
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: fetchAggregate — agrégation brute
    // ─────────────────────────────────────────────────────────

    public func fetchAggregate(
        rawQuery:  String,
        arguments: [AnyStorableArgument],
        namespace: String
    ) async throws -> [[String: Any]] {
        guard let searchEngine = engine as? SearchCapableEngine else {
            throw DatabaseError.engineUnavailable(
                reason: "fetchAggregate n'est supporté que par SQLiteEngine."
            )
        }
        return try await searchEngine.engineFetchAggregate(
            rawQuery:  rawQuery,
            arguments: arguments,
            namespace: namespace
        )
    }
}
