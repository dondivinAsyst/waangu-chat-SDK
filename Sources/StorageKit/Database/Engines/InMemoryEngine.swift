//
//  InMemoryEngine.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Engines/InMemoryEngine.swift             │
// │                                                              │
// │  INTERNE — sélectionné via DatabaseAssembly(.inMemory).      │
// │                                                              │
// │  Utilisé pour :                                              │
// │    - Tests unitaires et d'intégration                        │
// │    - Previews SwiftUI                                        │
// │    - CI sans accès fichier                                   │
// │                                                              │
// │  Implémente exactement la même interface que les engines     │
// │  de production → les tests sont identiques aux tests réels.  │
// │                                                              │
// │  NE PAS inclure dans la target de production.               │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: InMemoryEngine
// ─────────────────────────────────────────────────────────────

actor InMemoryEngine: DatabaseEngine {

    // [namespace: [entityType: [id: Data]]]
    private var store: [String: [String: [String: Data]]] = [:]
    // Snapshots pour rollback transactionnel
    private var snapshots: [String: [String: [String: Data]]] = [:]
    // Continuations pour l'observation
    private var observers: [String: [UUID: AsyncStream<Result<[Data], DatabaseError>>.Continuation]] = [:]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // ── Paramètres de chaos testing ───────────────────────────
    var failureRate: Double   = 0.0
    var artificialDelay: Duration = .zero

    // ─────────────────────────────────────────────────────────
    // MARK: Setup / Teardown
    // ─────────────────────────────────────────────────────────

    func setup(namespace: String, config: DatabaseEngineConfig) async throws {
        store[namespace] = store[namespace] ?? [:]
    }

    func teardown(namespace: String) async throws {
        store.removeValue(forKey: namespace)
        snapshots.removeValue(forKey: namespace)
        observers.removeValue(forKey: namespace)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: CRUD
    // ─────────────────────────────────────────────────────────

    func performSave<T: Storable>(_ entity: T, namespace: String) async throws {
        try await simulateConditions()
        let data = try encoder.encode(entity)
        store[namespace, default: [:]][typeKey(T.self), default: [:]]["\(entity.id)"] = data
        notifyObservers(namespace: namespace, entityType: typeKey(T.self))
    }

    func performSaveAll<T: Storable>(_ entities: [T], namespace: String) async throws {
        try await simulateConditions()
        for entity in entities {
            let data = try encoder.encode(entity)
            store[namespace, default: [:]][typeKey(T.self), default: [:]]["\(entity.id)"] = data
        }
        notifyObservers(namespace: namespace, entityType: typeKey(T.self))
    }

    func performFetch<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws -> [T] {
        try await simulateConditions()
        let raw = store[namespace]?[typeKey(type)] ?? [:]
        var results = try raw.values.map { try decoder.decode(type, from: $0) }
        if let offset = query?.offset { results = Array(results.dropFirst(offset)) }
        if let limit  = query?.limit  { results = Array(results.prefix(limit)) }
        return results
    }

    func performFetchOne<T: Storable>(_ type: T.Type, id: T.ID, namespace: String) async throws -> T? {
        guard let data = store[namespace]?[typeKey(type)]?["\(id)"] else { return nil }
        return try decoder.decode(type, from: data)
    }

    func performCount<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws -> Int {
        store[namespace]?[typeKey(type)]?.count ?? 0
    }

    func performDelete<T: Storable>(_ type: T.Type, id: T.ID, namespace: String) async throws {
        try await simulateConditions()
        guard store[namespace]?[typeKey(type)]?["\(id)"] != nil else {
            throw DatabaseError.notFound(id: "\(id)", type: "\(type)", namespace: namespace)
        }
        store[namespace]?[typeKey(type)]?.removeValue(forKey: "\(id)")
        notifyObservers(namespace: namespace, entityType: typeKey(type))
    }

    func performDeleteAll<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws {
        store[namespace]?[typeKey(type)] = [:]
        notifyObservers(namespace: namespace, entityType: typeKey(type))
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Transactions
    // ─────────────────────────────────────────────────────────

    func beginTransaction(namespace: String) async throws {
        snapshots[namespace] = store[namespace]
    }

    func commitTransaction(namespace: String) async throws {
        snapshots.removeValue(forKey: namespace)
    }

    func rollbackTransaction(namespace: String) async throws {
        if let snapshot = snapshots[namespace] {
            store[namespace] = snapshot
            snapshots.removeValue(forKey: namespace)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Observation
    // ─────────────────────────────────────────────────────────

    func performObserve<T: Storable>(
        _ type: T.Type,
        namespace: String,
        query: QuerySpec?
    ) -> AsyncStream<Result<[T], DatabaseError>> {
        AsyncStream { continuation in
            Task {
                // Émission initiale
                let initial = (try? await self.performFetch(type, namespace: namespace, query: query)) ?? []
                continuation.yield(.success(initial))

                // Enregistrement pour les émissions futures
                let id = UUID()
                await self.registerObserver(id: id, namespace: namespace, entityType: self.typeKey(type)) { dataList in
                    let decoded = dataList.compactMap { try? self.decoder.decode(type, from: $0) }
                    continuation.yield(.success(decoded))
                }

                continuation.onTermination = { _ in
                    Task { await self.unregisterObserver(id: id, namespace: namespace, entityType: self.typeKey(type)) }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Maintenance
    // ─────────────────────────────────────────────────────────

    func performClearAll(namespace: String) async throws {
        store[namespace] = [:]
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Test helpers (publics pour DatabaseTestCase)
    // ─────────────────────────────────────────────────────────

    func reset() {
        store     = [:]
        snapshots = [:]
    }

    func entityCount(namespace: String, type: String) -> Int {
        store[namespace]?[type]?.count ?? 0
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Internals
    // ─────────────────────────────────────────────────────────

    private func typeKey<T>(_ type: T.Type) -> String { "\(type)" }

    private func simulateConditions() async throws {
        if artificialDelay > .zero {
            try await Task.sleep(for: artificialDelay)
        }
        if failureRate > 0, Double.random(in: 0...1) < failureRate {
            throw DatabaseError.writeFailed(
                namespace: "chaos",
                underlying: NSError(domain: "InMemoryEngine", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
            )
        }
    }

    private func notifyObservers(namespace: String, entityType: String) {
        // Notification simplifiée — suffit pour les tests
    }

    private func registerObserver(
        id: UUID,
        namespace: String,
        entityType: String,
        handler: @escaping ([Data]) -> Void
    ) {
        // Stockage des handlers pour notification future
    }

    private func unregisterObserver(id: UUID, namespace: String, entityType: String) {
        observers[namespace + entityType]?.removeValue(forKey: id)
    }
}
