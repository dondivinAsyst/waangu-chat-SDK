//
//  ProductionEngineStubs.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Engines/ProductionEngineStubs.swift      │
// │                                                              │
// │  INTERNE — stubs des 4 engines de production.                │
// │                                                              │
// │  Chaque engine sera développé dans son propre fichier        │
// │  lors de l'étape dédiée :                                    │
// │    CoreDataEngine.swift   ← étape suivante                   │
// │    SwiftDataEngine.swift  ← étape après                      │
// │    SQLiteEngine.swift     ← étape après                      │
// │    RealmEngine.swift      ← étape après                      │
// │                                                              │
// │  Ces stubs garantissent que DatabaseAssembly compile          │
// │  dès maintenant sans attendre les implémentations complètes. │
// │  Chaque stub throw engineUnavailable() — comportement sûr.  │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import WaanguCoreKit


// ─────────────────────────────────────────────────────────────
// MARK: SwiftDataEngine — stub
// ─────────────────────────────────────────────────────────────

actor SwiftDataEngine: DatabaseEngine {
    func setup(namespace: String, config: DatabaseEngineConfig) async throws {
        throw DatabaseError.engineUnavailable(reason: "SwiftDataEngine non encore implémenté")
    }
    func teardown(namespace: String) async throws {}
    func performSave<T: Storable>(_ entity: T, namespace: String) async throws { try unavailable() }
    func performSaveAll<T: Storable>(_ entities: [T], namespace: String) async throws { try unavailable() }
    func performFetch<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws -> [T] { try unavailable() }
    func performFetchOne<T: Storable>(_ type: T.Type, id: T.ID, namespace: String) async throws -> T? { try unavailable() }
    func performCount<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws -> Int { try unavailable() }
    func performDelete<T: Storable>(_ type: T.Type, id: T.ID, namespace: String) async throws { try unavailable() }
    func performDeleteAll<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws { try unavailable() }
    func beginTransaction(namespace: String) async throws { try unavailable() }
    func commitTransaction(namespace: String) async throws {}
    func rollbackTransaction(namespace: String) async throws {}
    func performObserve<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) -> AsyncStream<Result<[T], DatabaseError>> {
        AsyncStream { $0.finish() }
    }
    func performClearAll(namespace: String) async throws { try unavailable() }
    private func unavailable() throws -> Never {
        throw DatabaseError.engineUnavailable(reason: "SwiftDataEngine non encore implémenté")
    }
}



// ─────────────────────────────────────────────────────────────
// MARK: RealmEngine — stub
// ─────────────────────────────────────────────────────────────

actor RealmEngine: DatabaseEngine {
    func setup(namespace: String, config: DatabaseEngineConfig) async throws {
        throw DatabaseError.engineUnavailable(reason: "RealmEngine non encore implémenté")
    }
    func teardown(namespace: String) async throws {}
    func performSave<T: Storable>(_ entity: T, namespace: String) async throws { try unavailable() }
    func performSaveAll<T: Storable>(_ entities: [T], namespace: String) async throws { try unavailable() }
    func performFetch<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws -> [T] { try unavailable() }
    func performFetchOne<T: Storable>(_ type: T.Type, id: T.ID, namespace: String) async throws -> T? { try unavailable() }
    func performCount<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws -> Int { try unavailable() }
    func performDelete<T: Storable>(_ type: T.Type, id: T.ID, namespace: String) async throws { try unavailable() }
    func performDeleteAll<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws { try unavailable() }
    func beginTransaction(namespace: String) async throws { try unavailable() }
    func commitTransaction(namespace: String) async throws {}
    func rollbackTransaction(namespace: String) async throws {}
    func performObserve<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) -> AsyncStream<Result<[T], DatabaseError>> {
        AsyncStream { $0.finish() }
    }
    func performClearAll(namespace: String) async throws { try unavailable() }
    private func unavailable() throws -> Never {
        throw DatabaseError.engineUnavailable(reason: "RealmEngine non encore implémenté")
    }
}
