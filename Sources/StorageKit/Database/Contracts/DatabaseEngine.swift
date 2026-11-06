//
//  DatabaseEngine.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Contracts/DatabaseEngine.swift           │
// │                                                              │
// │  INTERNE — jamais exporté hors de StorageKit.                │
// │  Seul DatabaseStore consomme ce protocol.                    │
// │                                                              │
// │  Chaque technologie implémente DatabaseEngine :              │
// │    CoreDataEngine, SwiftDataEngine, RealmEngine,             │
// │    SQLiteEngine, InMemoryEngine…                             │
// │                                                              │
// │  DatabaseStore ne sait pas lequel il utilise.                │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseEngine
// ─────────────────────────────────────────────────────────────

protocol DatabaseEngine: Actor {

    // ── Cycle de vie ──────────────────────────────────────────

    /// Initialise le store pour ce namespace.
    /// Appelé la première fois qu'une feature accède au namespace.
    /// Idempotent : un second appel avec le même namespace ne fait rien.
    func setup(namespace: String, config: DatabaseEngineConfig) async throws

    /// Libère les ressources du namespace (fichiers, connexions…).
    func teardown(namespace: String) async throws

    // ── CRUD ──────────────────────────────────────────────────

    func performSave<T: Storable>(_ entity: T, namespace: String) async throws
    func performSaveAll<T: Storable>(_ entities: [T], namespace: String) async throws
    func performFetch<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws -> [T]
    func performFetchOne<T: Storable>(_ type: T.Type, id: T.ID, namespace: String) async throws -> T?
    func performCount<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws -> Int
    func performDelete<T: Storable>(_ type: T.Type, id: T.ID, namespace: String) async throws
    func performDeleteAll<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws

    // ── Transactions ──────────────────────────────────────────

    func beginTransaction(namespace: String) async throws
    func commitTransaction(namespace: String) async throws
    func rollbackTransaction(namespace: String) async throws

    // ── Observation ───────────────────────────────────────────

    func performObserve<T: Storable>(
        _ type: T.Type,
        namespace: String,
        query: QuerySpec?
    ) -> AsyncStream<Result<[T], DatabaseError>>

    // ── Maintenance ───────────────────────────────────────────

    func performClearAll(namespace: String) async throws
}
