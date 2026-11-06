//
//  SQLiteMigrations.swift
//  AppModules
//
//  Created by Asyst on 5/18/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Migrations/SQLiteMigrations.swift        │
// │  INTERNE — jamais exposé hors de StorageKit                  │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import GRDB
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: SQLiteMigrationContext — INTERNE
// ─────────────────────────────────────────────────────────────

final class SQLiteMigrationContext: EngineMigrationContext, @unchecked Sendable {

    let namespace: String
    let db: Database

    init(namespace: String, db: Database) {
        self.namespace = namespace
        self.db        = db
    }

    func execute(_ sql: String) throws {
        try db.execute(sql: sql)
    }

    func tableExists(_ name: String) throws -> Bool {
        try db.tableExists(name)
    }

    func columnExists(_ column: String, in table: String) throws -> Bool {
        let columns = try db.columns(in: table)
        return columns.contains { $0.name == column }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: SQLiteMigrationStep — INTERNE
// ─────────────────────────────────────────────────────────────
// internal (pas public) car raffine EngineCapableMigrationStep
// qui est internal. Le App Target ne manipule jamais ce type
// directement — il passe par MigrationStep (CoreKit).

protocol SQLiteMigrationStep: EngineCapableMigrationStep {
    var migrationIdentifier: String { get }
    func validate(in context: SQLiteMigrationContext) async throws
    func perform(in context: SQLiteMigrationContext) async throws
    func rollback(in context: SQLiteMigrationContext) async throws
    func performSync(in context: SQLiteMigrationContext) throws
}

extension SQLiteMigrationStep {

    func validate(in context: any EngineMigrationContext) async throws {
        guard let ctx = context as? SQLiteMigrationContext else { return }
        try await validate(in: ctx)
    }

    func perform(in context: any EngineMigrationContext) async throws {
        guard let ctx = context as? SQLiteMigrationContext else { return }
        try await perform(in: ctx)
    }

    func rollback(in context: any EngineMigrationContext) async throws {
        guard let ctx = context as? SQLiteMigrationContext else { return }
        try await rollback(in: ctx)
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Étapes concrètes — PUBLIC
// ─────────────────────────────────────────────────────────────
// Ces structs sont public car le App Target les instancie
// dans databaseMigrationSteps(). Leurs méthodes internes
// (validate/perform/rollback) restent internal via le protocol.

// ── Ajout de colonne ─────────────────────────────────────────

 struct SQLiteAddColumnMigration: SQLiteMigrationStep {

    public let fromVersion:         Int
    public let toVersion:           Int
    let migrationIdentifier:        String    // internal — requis par SQLiteMigrationStep
    public var description:         String { migrationIdentifier }

    private let tableName:    String
    private let columnName:   String
    private let columnType:   String
    private let defaultValue: String?

    public init(
        from:     Int,
        to:       Int,
        table:    String,
        column:   String,
        type:     String,
        default:  String? = nil
    ) {
        self.fromVersion         = from
        self.toVersion           = to
        self.migrationIdentifier = "v\(to)_add_\(column)_to_\(table)"
        self.tableName           = table
        self.columnName          = column
        self.columnType          = type
        self.defaultValue        = `default`
    }

    func validate(in context: SQLiteMigrationContext) async throws {
        guard try context.tableExists(tableName) else {
            throw DatabaseError.migrationDryRunFailed(
                namespace: context.namespace, fromVersion: fromVersion,
                toVersion: toVersion, reason: "Table '\(tableName)' introuvable"
            )
        }
        if try context.columnExists(columnName, in: tableName) {
            throw DatabaseError.migrationDryRunFailed(
                namespace: context.namespace, fromVersion: fromVersion,
                toVersion: toVersion, reason: "Colonne '\(columnName)' existe déjà"
            )
        }
    }

    func perform(in context: SQLiteMigrationContext) async throws {
        try performSync(in: context)
    }

    func performSync(in context: SQLiteMigrationContext) throws {
        // Skip when v1 schema already created this column (fresh install).
        if try context.columnExists(columnName, in: tableName) { return }
        var sql = "ALTER TABLE \(tableName) ADD COLUMN \(columnName) \(columnType)"
        if let def = defaultValue { sql += " DEFAULT \(def)" }
        try context.execute(sql)
    }

    func rollback(in context: SQLiteMigrationContext) async throws {}
}

// ── Ajout d'index ─────────────────────────────────────────────

public struct SQLiteAddIndexMigration: SQLiteMigrationStep {

    public let fromVersion:         Int
    public let toVersion:           Int
    let migrationIdentifier:        String
    public var description:         String { migrationIdentifier }

    private let indexName: String
    private let tableName: String
    private let columns:   [String]
    private let unique:    Bool

    public init(
        from:    Int,
        to:      Int,
        index:   String,
        on table:String,
        columns: [String],
        unique:  Bool = false
    ) {
        self.fromVersion         = from
        self.toVersion           = to
        self.migrationIdentifier = "v\(to)_add_index_\(index)"
        self.indexName           = index
        self.tableName           = table
        self.columns             = columns
        self.unique              = unique
    }

    func validate(in context: SQLiteMigrationContext) async throws {
        guard try context.tableExists(tableName) else {
            throw DatabaseError.migrationDryRunFailed(
                namespace: context.namespace, fromVersion: fromVersion,
                toVersion: toVersion, reason: "Table '\(tableName)' introuvable"
            )
        }
    }

    func perform(in context: SQLiteMigrationContext) async throws {
        try performSync(in: context)
    }

    func performSync(in context: SQLiteMigrationContext) throws {
        let u    = unique ? "UNIQUE " : ""
        let cols = columns.joined(separator: ", ")
        try context.execute(
            "CREATE \(u)INDEX IF NOT EXISTS \(indexName) ON \(tableName) (\(cols))"
        )
    }

    func rollback(in context: SQLiteMigrationContext) async throws {
        try context.execute("DROP INDEX IF EXISTS \(indexName)")
    }
}

// ── Migration SQL arbitraire ──────────────────────────────────

public struct SQLiteRawMigration: SQLiteMigrationStep {

    public let fromVersion:         Int
    public let toVersion:           Int
    let migrationIdentifier:        String
    public var description:         String { migrationIdentifier }

    private let upSQL:   String
    private let downSQL: String?

    public init(
        from:       Int,
        to:         Int,
        identifier: String,
        up:         String,
        down:       String? = nil
    ) {
        self.fromVersion         = from
        self.toVersion           = to
        self.migrationIdentifier = identifier
        self.upSQL               = up
        self.downSQL             = down
    }

    func validate(in context: SQLiteMigrationContext) async throws {}

    func perform(in context: SQLiteMigrationContext) async throws {
        try performSync(in: context)
    }

    func performSync(in context: SQLiteMigrationContext) throws {
        try context.execute(upSQL)
    }

    func rollback(in context: SQLiteMigrationContext) async throws {
        if let down = downSQL { try context.execute(down) }
    }
}
