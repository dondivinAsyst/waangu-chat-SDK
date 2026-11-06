//
//  Databasestore.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/DatabaseStore.swift                      │
// │                                                              │
// │  Rôle : Adapter central.                                     │
// │  - Implémente DatabaseRepositoryProtocol (CoreKit)           │
// │  - Délègue à DatabaseEngine (interne StorageKit)             │
// │  - Gère le cycle de vie des namespaces (lazy init)           │
// │  - Instrumente chaque opération (métriques + OSSignpost)     │
// │  - Orchestre les transactions multi-namespace                 │
// │                                                              │
// │  Visibilité : interne StorageKit.                            │
// │  Le App Target ne le voit jamais — il passe par             │
// │  DatabaseAssembly.make() qui retourne DatabaseRepositoryProtocol. │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import OSLog
import WaanguCoreKit

private let log = OSLog(subsystem: "com.superapp.storagekit", category: "database")

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseStore
// ─────────────────────────────────────────────────────────────

public actor DatabaseStore: DatabaseRepositoryProtocol {

    // ── Dépendances ───────────────────────────────────────────
    // internal — accessible depuis DatabaseStore+Search (même module StorageKit)
    let engine: any DatabaseEngine
    private let slowQueryThreshold: Duration
    public weak var metricsDelegate: (any DatabaseMetricsDelegate)?

    // ── Config transmise par DatabaseAssembly ─────────────────
    // Contient migrationSteps — utilisée dans ensureReady()
    var sharedConfig: DatabaseEngineConfig?

    // ── État interne ──────────────────────────────────────────
    private var readyNamespaces: Set<String> = []
    /// Transactions ouvertes par ce store : jeton → namespaces engagés (B51).
    /// Un namespace ouvert pendant la transaction la rejoint (`joinOpenTransaction`).
    private var openTransactions: [UUID: [String]] = [:]

    // ─────────────────────────────────────────────────────────
    // MARK: Init
    // ─────────────────────────────────────────────────────────

    init(
        engine:             any DatabaseEngine,
        slowQueryThreshold: Duration = .milliseconds(16),
        metricsDelegate:    (any DatabaseMetricsDelegate)? = nil,
        sharedConfig:       DatabaseEngineConfig? = nil
    ) {
        self.engine             = engine
        self.slowQueryThreshold = slowQueryThreshold
        self.metricsDelegate    = metricsDelegate
        self.sharedConfig       = sharedConfig
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Enregistrement SQLiteStorable
    // ─────────────────────────────────────────────────────────

    /// Appelé par DatabaseAssembly.register() AVANT le premier accès.
    /// Délègue à SQLiteEngine pour mettre à jour son schemaBuilder.
    func registerSQLiteStorable<T: Storable>(_ type: T.Type) async {
     
        guard let sqliteEngine = engine as? SQLiteEngine else {
            debugLog("🔴 cast to SQLiteEngine FAILED — engine type: \(Swift.type(of: engine))")
            return
        }
        await sqliteEngine.register(type)
        #if DEBUG
        let registrations = await sqliteEngine.schemaBuilder.registrations
        debugLog("🟢 registered \(type) in schemaBuilder: \(registrations)")
        #endif
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Namespace lazy setup
    // ─────────────────────────────────────────────────────────

    private func ensureReady<T: Storable>(for type: T.Type) async throws {
        let ns = T.namespace
        guard !readyNamespaces.contains(ns) else { return }
        // Utilise sharedConfig si disponible (contient migrationSteps)
        // sinon config par défaut
        let cfg: DatabaseEngineConfig
        if let base = sharedConfig {
            cfg = DatabaseEngineConfig(
                namespace:      ns,
                storeDirectory: base.storeDirectory,
                encryptionKey:  base.encryptionKey,
                migrationSteps: base.migrationSteps
            )
        } else {
            cfg = .default(namespace: ns)
        }
        try await engine.setup(namespace: ns, config: cfg)
        readyNamespaces.insert(ns)
        try await joinOpenTransaction(ns)
    }

    private func ensureReady(namespace: String) async throws {
        guard !readyNamespaces.contains(namespace) else { return }
        let cfg: DatabaseEngineConfig
        if let base = sharedConfig {
            cfg = DatabaseEngineConfig(
                namespace:      namespace,
                storeDirectory: base.storeDirectory,
                encryptionKey:  base.encryptionKey,
                migrationSteps: base.migrationSteps
            )
        } else {
            cfg = .default(namespace: namespace)
        }
        try await engine.setup(namespace: namespace, config: cfg)
        readyNamespaces.insert(namespace)
        try await joinOpenTransaction(namespace)
    }

    /// Un namespace ouvert pour la première fois pendant une transaction de ce
    /// store y entre aussitôt. Sinon ses écritures — la première
    /// synchronisation après installation, typiquement — seraient validées une
    /// à une, hors de la transaction qui devait les couvrir.
    private func joinOpenTransaction(_ namespace: String) async throws {
        guard let token = SQLiteTransactionScope.token,
              let joined = openTransactions[token],
              !joined.contains(namespace) else { return }
        try await engine.beginTransaction(namespace: namespace)
        openTransactions[token, default: []].append(namespace)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: CRUD
    // ─────────────────────────────────────────────────────────

    public func save<T: Storable>(_ entity: T) async throws {
        try await ensureReady(for: T.self)
        try await measure(.save, namespace: T.namespace) {
            try await self.engine.performSave(entity, namespace: T.namespace)
        }
    }

    public func saveAll<T: Storable>(_ entities: [T]) async throws {
        guard !entities.isEmpty else { return }
        try await ensureReady(for: T.self)
        try await measure(.saveAll, namespace: T.namespace, rowCount: entities.count) {
            try await self.engine.performSaveAll(entities, namespace: T.namespace)
        }
    }

    public func fetch<T: Storable>(_ type: T.Type, query: QuerySpec? = nil) async throws -> [T] {
        try await ensureReady(for: type)
        return try await measure(.fetch, namespace: T.namespace) {
            try await self.engine.performFetch(type, namespace: T.namespace, query: query)
        }
    }

    public func fetchOne<T: Storable>(_ type: T.Type, id: T.ID) async throws -> T? {
        try await ensureReady(for: type)
        return try await measure(.fetchOne, namespace: T.namespace) {
            try await self.engine.performFetchOne(type, id: id, namespace: T.namespace)
        }
    }

    public func count<T: Storable>(_ type: T.Type, query: QuerySpec? = nil) async throws -> Int {
        try await ensureReady(for: type)
        return try await measure(.count, namespace: T.namespace) {
            try await self.engine.performCount(type, namespace: T.namespace, query: query)
        }
    }

    public func delete<T: Storable>(_ type: T.Type, id: T.ID) async throws {
        try await ensureReady(for: type)
        try await measure(.delete, namespace: T.namespace) {
            try await self.engine.performDelete(type, id: id, namespace: T.namespace)
        }
    }

    public func deleteAll<T: Storable>(_ type: T.Type, query: QuerySpec? = nil) async throws {
        try await ensureReady(for: type)
        try await measure(.deleteAll, namespace: T.namespace) {
            try await self.engine.performDeleteAll(type, namespace: T.namespace, query: query)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Transactions
    // ─────────────────────────────────────────────────────────

    public func withTransaction<R: Sendable>(
        _ block: @Sendable () async throws -> R
    ) async throws -> R {
        // B51 — une vraie transaction : le moteur ouvre `BEGIN IMMEDIATE`, les
        // écritures du bloc la rejoignent, et les autres tâches attendent la
        // fin. Le jeton identifie le bloc (et ses tâches enfants) auprès du
        // moteur ; il remplace le SAVEPOINT qui ne pouvait jamais committer (B49).

        // Imbriquée dans une transaction de ce store : refusée, plutôt que de
        // l'attendre alors qu'elle nous attend.
        if let outer = SQLiteTransactionScope.token, let joined = openTransactions[outer] {
            throw DatabaseError.transactionFailed(
                underlying: DatabaseError.transactionAlreadyActive(namespace: joined.first ?? "transaction")
            )
        }

        let token = UUID()
        return try await SQLiteTransactionScope.$token.withValue(token) {
            let start = ContinuousClock.now
            openTransactions[token] = []
            defer { openTransactions.removeValue(forKey: token) }

            do {
                // Ouvre une transaction sur tous les namespaces déjà initialisés,
                // toujours dans le même ordre : deux transactions qui verrouillent
                // dans un ordre différent s'attendraient l'une l'autre.
                for ns in readyNamespaces.sorted() {
                    try await engine.beginTransaction(namespace: ns)
                    openTransactions[token, default: []].append(ns)
                }

                let result = try await block()

                // Y compris les namespaces ouverts pendant le bloc.
                for ns in openTransactions[token] ?? [] {
                    try await engine.commitTransaction(namespace: ns)
                }

                let duration = ContinuousClock.now - start
                metricsDelegate?.database(
                    didExecute: QueryMetrics(
                        namespace: "transaction",
                        operation: .transaction,
                        duration: duration,
                        rowCount: 0,
                        slowThreshold: slowQueryThreshold
                    )
                )
                return result

            } catch {
                // Seuls les namespaces réellement engagés sont annulés.
                for ns in openTransactions[token] ?? [] {
                    try? await engine.rollbackTransaction(namespace: ns)
                }
                let wrapped = DatabaseError.transactionFailed(underlying: error)
                metricsDelegate?.database(
                    didFailWith: wrapped,
                    operation: .transaction,
                    namespace: "transaction"
                )
                throw wrapped
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Observation
    // ─────────────────────────────────────────────────────────

    public func observe<T: Storable>(
        _ type: T.Type,
        query: QuerySpec? = nil
    ) -> AsyncStream<Result<[T], DatabaseError>> {
        AsyncStream { continuation in
            Task {
                do {
                    try await self.ensureReady(for: type)
                    let stream = await self.engine.performObserve(
                        type,
                        namespace: T.namespace,
                        query: query
                    )
                    for await value in stream {
                        continuation.yield(value)
                    }
                } catch {
                    continuation.yield(.failure(.readFailed(namespace: T.namespace, underlying: error)))
                }
                continuation.finish()
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Maintenance
    // ─────────────────────────────────────────────────────────

    public func clearAll(namespace: String) async throws {
        try await ensureReady(namespace: namespace)
        try await measure(.clearAll, namespace: namespace) {
            try await self.engine.performClearAll(namespace: namespace)
        }
        // Le namespace reste "ready" — l'engine est toujours en place,
        // seules les données sont effacées.
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Instrumentation interne
    // ─────────────────────────────────────────────────────────

    @discardableResult
    private func measure<R>(
        _ operation: DatabaseOperation,
        namespace: String,
        rowCount: Int = 0,
        block: () async throws -> R
    ) async throws -> R {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "db_op", signpostID: id,
                    "%{public}s:%{public}s", operation.rawValue, namespace)
        let start = ContinuousClock.now

        do {
            let result = try await block()
            let duration = ContinuousClock.now - start

            os_signpost(.end, log: log, name: "db_op", signpostID: id,
                        "rows=%d ms=%d", rowCount, duration.milliseconds)

            let rows: Int = {
                if let arr = result as? [any Storable] { return arr.count }
                if let n   = result as? Int            { return n }
                return rowCount
            }()

            let metrics = QueryMetrics(
                namespace: namespace,
                operation: operation,
                duration: duration,
                rowCount: rows,
                slowThreshold: slowQueryThreshold
            )

            if metrics.isSlowQuery {
                os_log(.error, log: log,
                       "SLOW [%{public}s] %{public}s — %d ms",
                       namespace, operation.rawValue, duration.milliseconds)
            }

            metricsDelegate?.database(didExecute: metrics)
            return result

        } catch let err as DatabaseError {
            os_signpost(.end, log: log, name: "db_op", signpostID: id, "FAILED")
            metricsDelegate?.database(didFailWith: err, operation: operation, namespace: namespace)
            throw err

        } catch {
            os_signpost(.end, log: log, name: "db_op", signpostID: id, "FAILED")
            let wrapped: DatabaseError = switch operation {
            case .fetch, .fetchOne, .count, .observe:
                .readFailed(namespace: namespace, underlying: error)
            default:
                .writeFailed(namespace: namespace, underlying: error)
            }
            metricsDelegate?.database(didFailWith: wrapped, operation: operation, namespace: namespace)
            throw wrapped
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Duration helper (interne StorageKit)
// ─────────────────────────────────────────────────────────────

extension Duration {
    var milliseconds: Int {
        Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
    }

    static func milliseconds(_ ms: Int) -> Duration {
        .init(
            secondsComponent:     Int64(ms / 1_000),
            attosecondsComponent: Int64(ms % 1_000) * 1_000_000_000_000_000
        )
    }
}
