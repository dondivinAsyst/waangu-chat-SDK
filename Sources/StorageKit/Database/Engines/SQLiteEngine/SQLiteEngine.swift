// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Engines/SQLiteEngine.swift               │
// │                                                              │
// │  INTERNE — sélectionné via DatabaseAssembly(.sqlite).        │
// │  Dépendance : GRDB                                           │
// │                                                              │
// │  Deux modes de stockage :                                    │
// │    - Entité enregistrée → table SQL dédiée + json_payload    │
// │    - Entité non enregistrée → table proxy JSON (entity_proxy)│
// │                                                              │
// │  La distinction se fait par présence d'une registration      │
// │  dans schemaBuilder, PAS par conformité de type.             │
// │                                                              │
// │  Toutes les méthodes GRDB sont statiques et synchrones       │
// │  (closures GRDB incompatibles avec actor isolation).         │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import GRDB
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: SQLiteEngine
// ─────────────────────────────────────────────────────────────

actor SQLiteEngine: DatabaseEngine {

    var queues:        [String: DatabaseQueue] = [:]
    var inTransaction: [String: Bool]          = [:]
    /// Namespace → jeton de la tâche qui y tient une transaction ouverte (B51).
    var transactionOwners: [String: UUID]      = [:]
    /// Tâches en attente de la fin d'une transaction, par namespace.
    var transactionWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    var schemaBuilder: SQLiteSchemaBuilder     = SQLiteSchemaBuilder()

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // ─────────────────────────────────────────────────────────
    // MARK: Register
    // ─────────────────────────────────────────────────────────

    func register<T: Storable>(_ type: T.Type) {
        schemaBuilder.register(type, namespace: T.namespace)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Setup
    // ─────────────────────────────────────────────────────────

    func setup(namespace: String, config: DatabaseEngineConfig) async throws {
        guard queues[namespace] == nil else { return }

        try FileManager.default.createDirectory(
            at: config.storeDirectory, withIntermediateDirectories: true
        )

        let dbURL = config.storeDirectory.appending(path: "\(namespace).sqlite")

        var grdbConfig = Configuration()
        grdbConfig.label              = "com.superapp.storagekit.\(namespace)"
        grdbConfig.maximumReaderCount = 5
        // B51 — `withTransaction` ouvre `BEGIN IMMEDIATE` dans un accès et le
        // valide dans un autre, après les écritures du bloc. GRDB l'interdit par
        // défaut ; la porte `gatedQueue` garantit qu'aucune autre tâche n'utilise
        // la connexion pendant ce temps.
        grdbConfig.allowsUnsafeTransactions = true

        let queue = try DatabaseQueue(path: dbURL.path, configuration: grdbConfig)

        let currentSchema = schemaBuilder

        var migrator = DatabaseMigrator()

        let registeredTables = schemaBuilder.registrations[namespace]?
            .map { $0.tableName }
            .sorted()
            .joined(separator: "_") ?? "empty"
        let migrationName = "v1_schema_\(registeredTables)"

        migrator.registerMigration(migrationName) { db in
            try currentSchema.createSchema(in: db, namespace: namespace)
        }

        // ── Migrations supplémentaires ─────────────────────────

        // A. FieldMigration agnostiques (CoreKit) → traduites en SQL
        let regs = currentSchema.registrations[namespace] ?? []
        let fieldMigrations = config.migrationSteps
            .compactMap { $0 as? FieldMigration }
            // `migrationSteps` est partagé par toutes les bases. Une migration ne vaut que
            // pour le namespace qui enregistre son entité : ailleurs, le nom de table de
            // repli (`sync_statusmodels`) n'existe pas et l'ouverture de la base échouait.
            .filter { field in regs.contains { $0.entityType == field.entityName } }
            .sorted { $0.fromVersion < $1.fromVersion }

        for field in fieldMigrations {
            let sqlStep = FieldMigrationTranslator.translate(
                field, namespace: namespace, registrations: regs
            )
            migrator.registerMigration(sqlStep.migrationIdentifier) { db in
                let ctx = SQLiteMigrationContext(namespace: namespace, db: db)
                try sqlStep.performSync(in: ctx)
            }
        }

        // B. SQLiteMigrationStep explicites (cas complexes — compromis assumé)
        let sqliteSteps = config.migrationSteps
            .compactMap { $0 as? any SQLiteMigrationStep }
            .sorted { $0.fromVersion < $1.toVersion }

        for step in sqliteSteps {
            let s = step
            migrator.registerMigration(s.migrationIdentifier) { db in
                let ctx = SQLiteMigrationContext(namespace: namespace, db: db)
                try s.performSync(in: ctx)
            }
        }

        try migrator.migrate(queue)

        let encryptionManager = DatabaseEncryptionManager.shared
        Task.detached { await encryptionManager.applyFileProtection(to: dbURL) }

        queues[namespace] = queue
    }

    func teardown(namespace: String) async throws {
        queues.removeValue(forKey: namespace)
        inTransaction.removeValue(forKey: namespace)
        releaseTransaction(namespace: namespace)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Queue helper
    // ─────────────────────────────────────────────────────────

    func queue(for namespace: String) throws -> DatabaseQueue {
        guard let q = queues[namespace] else {
            throw WaanguCoreKit.DatabaseError.namespaceNotReady(namespace)
        }
        return q
    }

    /// La file du namespace, une fois libre pour la tâche courante (B51).
    ///
    /// Pendant une transaction, seule la tâche qui la tient (et ses tâches
    /// enfants, qui héritent du jeton) passe ; les autres attendent la fin.
    func gatedQueue(for namespace: String) async throws -> DatabaseQueue {
        while let owner = transactionOwners[namespace], owner != SQLiteTransactionScope.token {
            await withCheckedContinuation { continuation in
                transactionWaiters[namespace, default: []].append(continuation)
            }
        }
        return try queue(for: namespace)
    }

    private func releaseTransaction(namespace: String) {
        transactionOwners.removeValue(forKey: namespace)
        inTransaction[namespace] = false
        let waiting = transactionWaiters.removeValue(forKey: namespace) ?? []
        waiting.forEach { $0.resume() }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Registration check
    // ─────────────────────────────────────────────────────────
    // Détermine si une entité a une table dédiée (enregistrée)
    // ou passe par le proxy JSON générique.
    // NE PAS utiliser `type is any Storable.Type` — c'est toujours true.

    private func hasDedicatedTable<T: Storable>(_ type: T.Type) -> Bool {
        schemaBuilder.registrations[T.namespace]?
            .contains { $0.entityType == "\(type)" } ?? false
    }

    private func registration<T: Storable>(for type: T.Type) -> SQLiteEntityRegistration? {
        schemaBuilder.registrations[T.namespace]?
            .first { $0.entityType == "\(type)" }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: CRUD — actor methods → static delegation
    // ─────────────────────────────────────────────────────────

    func performSave<T: Storable>(_ entity: T, namespace: String) async throws {
        let q   = try await gatedQueue(for: namespace)
        let enc = encoder
        let reg = registration(for: T.self)
        try SQLiteEngine.staticSave(
            entity: entity, namespace: namespace,
            q: q, encoder: enc, registration: reg
        )
    }

    func performSaveAll<T: Storable>(_ entities: [T], namespace: String) async throws {
        guard !entities.isEmpty else { return }
        let q    = try await gatedQueue(for: namespace)
        let enc  = encoder
        let regs = schemaBuilder.registrations[namespace] ?? []
        try SQLiteEngine.staticSaveAll(
            entities: entities, namespace: namespace,
            q: q, encoder: enc, registrations: regs
        )
    }

    func performFetch<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws -> [T] {
        let q   = try await gatedQueue(for: namespace)
        let dec = decoder
        let ded = hasDedicatedTable(type)
        return try SQLiteEngine.staticFetch(
            type, namespace: namespace, query: query,
            q: q, decoder: dec, hasDedicatedTable: ded
        )
    }

    func performFetchOne<T: Storable>(_ type: T.Type, id: T.ID, namespace: String) async throws -> T? {
        let q   = try await gatedQueue(for: namespace)
        let dec = decoder
        let ded = hasDedicatedTable(type)
        return try SQLiteEngine.staticFetchOne(
            type, id: id, namespace: namespace,
            q: q, decoder: dec, hasDedicatedTable: ded
        )
    }

    func performCount<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws -> Int {
        let q   = try await gatedQueue(for: namespace)
        let ded = hasDedicatedTable(type)
        return try SQLiteEngine.staticCount(
            type, namespace: namespace, query: query,
            q: q, hasDedicatedTable: ded
        )
    }

    func performDelete<T: Storable>(_ type: T.Type, id: T.ID, namespace: String) async throws {
        let q   = try await gatedQueue(for: namespace)
        let ded = hasDedicatedTable(type)
        try SQLiteEngine.staticDelete(
            type, id: id, namespace: namespace,
            q: q, hasDedicatedTable: ded
        )
    }

    func performDeleteAll<T: Storable>(_ type: T.Type, namespace: String, query: QuerySpec?) async throws {
        let q   = try await gatedQueue(for: namespace)
        let ded = hasDedicatedTable(type)
        try SQLiteEngine.staticDeleteAll(
            type, namespace: namespace, query: query,
            q: q, hasDedicatedTable: ded
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Transactions — une vraie transaction SQLite (B51)
    // ─────────────────────────────────────────────────────────
    //
    // Avant, `SAVEPOINT` et `RELEASE` s'exécutaient chacun dans leur propre
    // `write` GRDB, déjà transactionnel : le savepoint disparaissait au commit
    // de cette écriture, le commit échouait toujours et le rollback ne défaisait
    // rien (B49). Ici `BEGIN IMMEDIATE` reste ouvert à travers les écritures du
    // bloc, qui le rejoignent par `writeJoiningTransaction`, et la porte
    // `gatedQueue` fait attendre les autres tâches.

    func beginTransaction(namespace: String) async throws {
        guard let token = SQLiteTransactionScope.token else {
            throw WaanguCoreKit.DatabaseError.engineUnavailable(
                reason: "beginTransaction requires DatabaseStore.withTransaction (no transaction scope)."
            )
        }
        guard transactionOwners[namespace] != token else {
            throw WaanguCoreKit.DatabaseError.transactionAlreadyActive(namespace: namespace)
        }
        let q = try await gatedQueue(for: namespace)
        // Claim the namespace **before** the `await` below. The actor is free
        // while `BEGIN` runs: claiming afterwards let a second task through the
        // gate, and SQLite refused its own `BEGIN` ("cannot start a transaction
        // within a transaction") — seen live on 2026-10-14.
        transactionOwners[namespace] = token
        inTransaction[namespace] = true
        do {
            try await q.writeWithoutTransaction { db in try db.execute(sql: "BEGIN IMMEDIATE TRANSACTION") }
        } catch {
            releaseTransaction(namespace: namespace)
            throw error
        }
    }

    func commitTransaction(namespace: String) async throws {
        guard let token = SQLiteTransactionScope.token, transactionOwners[namespace] == token else { return }
        let q = try queue(for: namespace)
        defer { releaseTransaction(namespace: namespace) }
        try await q.writeWithoutTransaction { db in try db.execute(sql: "COMMIT TRANSACTION") }
    }

    func rollbackTransaction(namespace: String) async throws {
        guard let token = SQLiteTransactionScope.token, transactionOwners[namespace] == token else { return }
        let q = try queue(for: namespace)
        defer { releaseTransaction(namespace: namespace) }
        try await q.writeWithoutTransaction { db in
            if db.isInsideTransaction { try db.execute(sql: "ROLLBACK TRANSACTION") }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Observation — GRDB ValueObservation
    // ─────────────────────────────────────────────────────────

    func performObserve<T: Storable>(
        _ type: T.Type, namespace: String, query: QuerySpec?
    ) -> AsyncStream<Result<[T], WaanguCoreKit.DatabaseError>> {
        let dec = decoder
        let ded = hasDedicatedTable(type)
        return AsyncStream { continuation in
            Task {
                // Une observation qui démarre pendant une transaction ouverte
                // déclencherait la précondition GRDB de `spawnConcurrentRead` :
                // elle attend la fin, comme toute autre opération (B51).
                guard let q = try? await self.gatedQueue(for: namespace) else {
                    continuation.yield(.failure(.namespaceNotReady(namespace)))
                    continuation.finish()
                    return
                }

                // Émission initiale
                do {
                    let initial = try SQLiteEngine.staticFetch(
                        type, namespace: namespace, query: query,
                        q: q, decoder: dec, hasDedicatedTable: ded
                    )
                    continuation.yield(.success(initial))
                } catch {
                    continuation.yield(.failure(
                        .readFailed(namespace: namespace, underlying: error)
                    ))
                }

                // GRDB ValueObservation — émet à chaque modification
                let observation = ValueObservation.tracking { db -> [T] in
                    if ded {
                        return (try? SQLiteEngine.fetchFromDedicatedTable(
                            type, namespace: namespace, query: query,
                            db: db, decoder: dec
                        )) ?? []
                    } else {
                        return (try? SQLiteEngine.fetchFromProxy(
                            type, namespace: namespace, query: query,
                            db: db, decoder: dec
                        )) ?? []
                    }
                }

                let cancellable = observation.start(
                    in: q,
                    scheduling: .async(onQueue: .global())
                ) { error in
                    continuation.yield(.failure(
                        .readFailed(namespace: namespace, underlying: error)
                    ))
                } onChange: { results in
                    continuation.yield(.success(results))
                }

                continuation.onTermination = { _ in cancellable.cancel() }
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Maintenance
    // ─────────────────────────────────────────────────────────

    func performClearAll(namespace: String) async throws {
        let q = try await gatedQueue(for: namespace)
        try SQLiteEngine.staticClearAll(namespace: namespace, q: q)
    }

    // ═════════════════════════════════════════════════════════
    // MARK: — Méthodes statiques — synchrones, nonisolated
    // ═════════════════════════════════════════════════════════
    // GRDB write/read closures sont synchrones et non-isolated.
    // Pas d'async ici — jamais.

    // ─────────────────────────────────────────────────────────
    // MARK: Save
    // ─────────────────────────────────────────────────────────

    static func staticSave<T: Storable>(
        entity: T, namespace: String,
        q: DatabaseQueue, encoder: JSONEncoder,
        registration: SQLiteEntityRegistration?
    ) throws {
        let data = try encoder.encode(entity)
        try SQLiteEngine.writeJoiningTransaction(q) { db in
            if registration != nil {
                try upsertInDedicatedTable(
                    entity, data: data, namespace: namespace,
                    registration: registration, db: db
                )
            } else {
                try upsertProxy(
                    id: "\(entity.id)", type: "\(T.self)",
                    namespace: namespace, data: data, db: db
                )
            }
        }
    }

    static func staticSaveAll<T: Storable>(
        entities: [T], namespace: String,
        q: DatabaseQueue, encoder: JSONEncoder,
        registrations: [SQLiteEntityRegistration]
    ) throws {
        try SQLiteEngine.writeJoiningTransaction(q) { db in
            for entity in entities {
                let data = try encoder.encode(entity)
                let reg  = registrations.first { $0.entityType == "\(type(of: entity))" }
                if reg != nil {
                    try upsertInDedicatedTable(
                        entity, data: data, namespace: namespace,
                        registration: reg, db: db
                    )
                } else {
                    try upsertProxy(
                        id: "\(entity.id)", type: "\(T.self)",
                        namespace: namespace, data: data, db: db
                    )
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Fetch
    // ─────────────────────────────────────────────────────────

    static func staticFetch<T: Storable>(
        _ type: T.Type, namespace: String, query: QuerySpec?,
        q: DatabaseQueue, decoder: JSONDecoder, hasDedicatedTable: Bool
    ) throws -> [T] {
        try q.read { db in
            if hasDedicatedTable {
                return try fetchFromDedicatedTable(
                    type, namespace: namespace, query: query,
                    db: db, decoder: decoder
                )
            } else {
                return try fetchFromProxy(
                    type, namespace: namespace, query: query,
                    db: db, decoder: decoder
                )
            }
        }
    }

    static func staticFetchOne<T: Storable>(
        _ type: T.Type, id: T.ID, namespace: String,
        q: DatabaseQueue, decoder: JSONDecoder, hasDedicatedTable: Bool
    ) throws -> T? {
        let idStr   = "\(id)"
        let typeStr = "\(type)"
        return try q.read { db in
            if hasDedicatedTable {
                let table = SQLiteSchemaBuilder.tableName(for: type)
                guard let row = try Row.fetchOne(
                    db, sql: "SELECT * FROM \(table) WHERE id = ?",
                    arguments: [idStr]
                ), let data = row["json_payload"] as? Data else { return nil }
                return try? decoder.decode(type, from: data)
            } else {
                guard let row = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM entity_proxy WHERE entity_id = ? AND entity_type = ?",
                    arguments: [idStr, typeStr]
                ), let data = row["json_payload"] as? Data else { return nil }
                return try? decoder.decode(type, from: data)
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Count
    // ─────────────────────────────────────────────────────────

    static func staticCount<T: Storable>(
        _ type: T.Type, namespace: String, query: QuerySpec?,
        q: DatabaseQueue, hasDedicatedTable: Bool
    ) throws -> Int {
        let typeStr = "\(type)"
        return try q.read { db in
            if hasDedicatedTable {
                let table = SQLiteSchemaBuilder.tableName(for: type)
                var sql = "SELECT COUNT(*) FROM \(table)"
                let (suffix, args) = sqlQuerySuffix(from: query)
                if !suffix.isEmpty { sql += " \(suffix)" }
                return try Int.fetchOne(
                    db, sql: sql, arguments: StatementArguments(args)
                ) ?? 0
            } else {
                return try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM entity_proxy WHERE entity_type = ?",
                    arguments: [typeStr]
                ) ?? 0
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Delete
    // ─────────────────────────────────────────────────────────

    static func staticDelete<T: Storable>(
        _ type: T.Type, id: T.ID, namespace: String,
        q: DatabaseQueue, hasDedicatedTable: Bool
    ) throws {
        let idStr   = "\(id)"
        let typeStr = "\(type)"
        let deleted: Bool = try SQLiteEngine.writeJoiningTransaction(q) { db in
            if hasDedicatedTable {
                let table = SQLiteSchemaBuilder.tableName(for: type)
                try db.execute(
                    sql: "DELETE FROM \(table) WHERE id = ?",
                    arguments: [idStr]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM entity_proxy WHERE entity_id = ? AND entity_type = ?",
                    arguments: [idStr, typeStr]
                )
            }
            return db.changesCount > 0
        }
        if !deleted {
            throw WaanguCoreKit.DatabaseError.notFound(
                id: idStr, type: typeStr, namespace: namespace
            )
        }
    }

    static func staticDeleteAll<T: Storable>(
        _ type: T.Type, namespace: String, query: QuerySpec?,
        q: DatabaseQueue, hasDedicatedTable: Bool
    ) throws {
        let typeStr = "\(type)"
        try SQLiteEngine.writeJoiningTransaction(q) { db in
            if hasDedicatedTable {
                let table = SQLiteSchemaBuilder.tableName(for: type)
                var sql = "DELETE FROM \(table)"
                let (suffix, args) = sqlQuerySuffix(from: query, includeSort: false)
                if !suffix.isEmpty { sql += " \(suffix)" }
                try db.execute(sql: sql, arguments: StatementArguments(args))
            } else {
                try db.execute(
                    sql: "DELETE FROM entity_proxy WHERE entity_type = ?",
                    arguments: [typeStr]
                )
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Exec / ClearAll
    // ─────────────────────────────────────────────────────────

    /// Écriture qui rejoint la transaction ouverte s'il y en a une (B51).
    ///
    /// `DatabaseQueue.write` ouvre toujours sa propre transaction, ce qui
    /// échoue dans une transaction déjà ouverte. `inSavepoint` ouvre une
    /// transaction quand il n'y en a pas — exactement `write` — et un
    /// savepoint imbriqué sinon : l'écriture reste atomique et appartient à la
    /// transaction englobante.
    static func writeJoiningTransaction<T>(_ q: DatabaseQueue, _ updates: (Database) throws -> T) throws -> T {
        try q.writeWithoutTransaction { db in
            var result: T?
            try db.inSavepoint {
                result = try updates(db)
                return .commit
            }
            return result!
        }
    }

    static func staticExec(_ sql: String, q: DatabaseQueue) throws {
        try SQLiteEngine.writeJoiningTransaction(q) { db in try db.execute(sql: sql) }
    }

    static func staticClearAll(namespace: String, q: DatabaseQueue) throws {
        try SQLiteEngine.writeJoiningTransaction(q) { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE ?",
                arguments: ["\(namespace)_%"]
            )
            for table in tables {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            try db.execute(
                sql: "DELETE FROM entity_proxy WHERE namespace = ?",
                arguments: [namespace]
            )
        }
    }

    // ═════════════════════════════════════════════════════════
    // MARK: — Helpers SQL
    // ═════════════════════════════════════════════════════════

    // ─────────────────────────────────────────────────────────
    // MARK: Upsert — table dédiée
    // ─────────────────────────────────────────────────────────

    static func upsertInDedicatedTable<T: Storable>(
        _ entity: T, data: Data,
        namespace: String,
        registration: SQLiteEntityRegistration?,
        db: Database
    ) throws {
        try entity.openForUpsert(
            data: data, namespace: namespace,
            registration: registration, db: db
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Upsert — proxy JSON
    // ─────────────────────────────────────────────────────────

    static func upsertProxy(
        id: String, type: String, namespace: String,
        data: Data, db: Database
    ) throws {
        let now = Date().timeIntervalSinceReferenceDate
        try db.execute(
            sql: """
                INSERT INTO entity_proxy
                    (entity_id, entity_type, namespace, json_payload, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(entity_id) DO UPDATE SET
                    json_payload = excluded.json_payload,
                    updated_at   = excluded.updated_at
                """,
            arguments: [id, type, namespace, data, now, now]
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Fetch — table dédiée
    // ─────────────────────────────────────────────────────────

    static func fetchFromDedicatedTable<T: Storable>(
        _ type: T.Type, namespace: String, query: QuerySpec?,
        db: Database, decoder: JSONDecoder
    ) throws -> [T] {
        let table = SQLiteSchemaBuilder.tableName(for: type)
        var sql   = "SELECT * FROM \(table)"
        let (suffix, args) = sqlQuerySuffix(from: query)
        if !suffix.isEmpty { sql += " \(suffix)" }

        return try Row.fetchAll(
            db, sql: sql, arguments: StatementArguments(args)
        ).compactMap { row in
            guard let data = row["json_payload"] as? Data else { return nil }
            return try? decoder.decode(type, from: data)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Fetch — proxy JSON
    // ─────────────────────────────────────────────────────────

    static func fetchFromProxy<T: Storable>(
        _ type: T.Type, namespace: String, query: QuerySpec?,
        db: Database, decoder: JSONDecoder
    ) throws -> [T] {
        var sql  = "SELECT * FROM entity_proxy WHERE entity_type = ?"
        var args: [DatabaseValueConvertible] = ["\(type)"]
        if let limit  = query?.limit  { sql += " LIMIT \(limit)"   }
        if let offset = query?.offset { sql += " OFFSET \(offset)" }

        return try Row.fetchAll(
            db, sql: sql, arguments: StatementArguments(args)
        ).compactMap { row in
            guard let data = row["json_payload"] as? Data else { return nil }
            return try? decoder.decode(type, from: data)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Extract field from JSON
    // ─────────────────────────────────────────────────────────

    static func extractField(
        _ fieldName: String, from data: Data
    ) -> DatabaseValueConvertible? {
        guard let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return nil }

        let camelCase = snakeToCamel(fieldName)
        let value     = json[fieldName] ?? json[camelCase]
        guard let value else { return nil }

        switch value {
        case let s as String: return s
        case let i as Int:    return i
        case let d as Double: return d
        case let b as Bool:   return b
        default:              return "\(value)"
        }
    }

    private static func snakeToCamel(_ input: String) -> String {
        let parts = input.split(separator: "_")
        guard let first = parts.first else { return input }
        let rest = parts.dropFirst()
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return ([String(first)] + rest).joined()
    }

    // ─────────────────────────────────────────────────────────
    // MARK: SQL query builder
    // ─────────────────────────────────────────────────────────

    /// Translates FilterSpec into a SQLite WHERE clause.
    static func translateFilter(
        _ filter: FilterSpec
    ) -> (clause: String, arguments: [DatabaseValueConvertible]) {
        var clause = filter.format
        clause = clause.replacingOccurrences(of: "==", with: "=")
        clause = clause.replacingOccurrences(of: "%@", with: "?")
        let arguments = filter.arguments.compactMap { $0.asDatabaseValue }
        return (clause, arguments)
    }

    /// Builds WHERE / ORDER BY / LIMIT / OFFSET suffix.
    static func sqlQuerySuffix(
        from query: QuerySpec?,
        includeSort: Bool = true
    ) -> (suffix: String, arguments: [DatabaseValueConvertible]) {
        var parts: [String] = []
        var args: [DatabaseValueConvertible] = []

        if let filter = query?.filter {
            let translated = translateFilter(filter)
            parts.append("WHERE \(translated.clause)")
            args += translated.arguments
        }
        if includeSort, let sorts = query?.sort, !sorts.isEmpty {
            parts.append(
                "ORDER BY " + sorts
                    .map { "\($0.keyPath) \($0.ascending ? "ASC" : "DESC")" }
                    .joined(separator: ", ")
            )
        }
        if let limit = query?.limit {
            parts.append("LIMIT \(limit)")
        }
        if let offset = query?.offset {
            parts.append("OFFSET \(offset)")
        }
        return (parts.joined(separator: " "), args)
    }
    
    
    // SQLiteEngine.swift — custom request

    func performRawFetch<T: Storable>(
        _ type: T.Type,
        rawQuery: String,
        arguments: [AnyStorableArgument],
        namespace: String
    ) async throws -> [T] {
        let q   = try await gatedQueue(for: namespace)
        let dec = decoder
        let args = arguments.compactMap { $0.asDatabaseValue }
        return try SQLiteEngine.staticRawFetch(
            type, rawQuery: rawQuery, args: args, q: q, decoder: dec
        )
    }

    func performRawAggregate(
        rawQuery: String,
        arguments: [AnyStorableArgument],
        namespace: String
    ) async throws -> [[String: Any]] {
        let q    = try await gatedQueue(for: namespace)
        let args = arguments.compactMap { $0.asDatabaseValue }
        return try SQLiteEngine.staticRawAggregate(
            rawQuery: rawQuery, args: args, q: q
        )
    }

    // ── Méthodes statiques ──────────────────────────────────────

    static func staticRawFetch<T: Storable>(
        _ type: T.Type,
        rawQuery: String,
        args: [DatabaseValueConvertible],
        q: DatabaseQueue,
        decoder: JSONDecoder
    ) throws -> [T] {
        try q.read { db in
            let rows = try Row.fetchAll(
                db, sql: rawQuery, arguments: StatementArguments(args)
            )
            return rows.compactMap { row in
                guard let data = row["json_payload"] as? Data else { return nil }
                return try? decoder.decode(type, from: data)
            }
        }
    }

    static func staticRawAggregate(
        rawQuery: String,
        args: [DatabaseValueConvertible],
        q: DatabaseQueue
    ) throws -> [[String: Any]] {
        try q.read { db in
            let rows = try Row.fetchAll(
                db, sql: rawQuery, arguments: StatementArguments(args)
            )
            return rows.map { row in
                Dictionary(uniqueKeysWithValues: row.columnNames.map { col in
                    (col, row[col] as Any)
                })
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: AnyStorableArgument → DatabaseValueConvertible
// ─────────────────────────────────────────────────────────────

extension AnyStorableArgument {
    var asDatabaseValue: DatabaseValueConvertible? {
        switch self {
        case .string(let s): return s
        case .int(let i):    return i
        case .double(let d): return d
        case .bool(let b):   return b
        case .uuid(let u):   return u.uuidString
        case .date(let d):   return d.timeIntervalSinceReferenceDate
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Storable — ouverture d'existentiel pour upsert
// ─────────────────────────────────────────────────────────────

extension Storable {
    func openForUpsert(
        data:         Data,
        namespace:    String,
        registration: SQLiteEntityRegistration?,
        db:           Database
    ) throws {
        let table    = SQLiteSchemaBuilder.tableName(for: Self.self)
        let now      = Date().timeIntervalSinceReferenceDate
        let entityId = "\(self.id)"

        var columns = ["id", "json_payload", "created_at", "updated_at"]
        var values:  [DatabaseValueConvertible?] = [entityId, data, now, now]

        if let reg = registration {
            for field in reg.indexedFields {
                columns.append(field)
                values.append(SQLiteEngine.extractField(field, from: data))
            }
            let alreadyAdded = Set(reg.indexedFields)
            for field in reg.fulltextFields where !alreadyAdded.contains(field) {
                columns.append(field)
                values.append(SQLiteEngine.extractField(field, from: data))
            }
            let allAdded = alreadyAdded.union(Set(reg.fulltextFields))
            for fk in reg.foreignKeys
                where !columns.contains(fk.column) && !allAdded.contains(fk.column)
            {
                columns.append(fk.column)
                values.append(SQLiteEngine.extractField(fk.column, from: data))
            }
        }

        let placeholders  = columns.map { _ in "?" }.joined(separator: ", ")
        let updateClauses = columns
            .filter { $0 != "id" && $0 != "created_at" }
            .map    { "\($0) = excluded.\($0)" }
            .joined(separator: ", ")

        try db.execute(
            sql: """
                INSERT INTO \(table) (\(columns.joined(separator: ", ")))
                VALUES (\(placeholders))
                ON CONFLICT(id) DO UPDATE SET \(updateClauses)
                """,
            arguments: StatementArguments(values)
        )
    }
}
