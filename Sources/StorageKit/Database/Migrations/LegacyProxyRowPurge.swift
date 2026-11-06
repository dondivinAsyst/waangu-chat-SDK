//
//  LegacyProxyRowPurge.swift
//  StorageKit
//
//  One-time cleanup for a `Storable` that shipped unregistered and was later
//  added to a `DatabaseRegistrable`.
//
//  While unregistered, its rows were written to the shared `entity_proxy` JSON
//  table. Registration gives the type its own table, and every read and write
//  moves there — leaving the old proxy rows orphaned: unreachable through the
//  repository API, invisible to the feature, and never cleaned up.
//
//  This step deletes them.
//

import Foundation
import GRDB
import WaanguCoreKit

public struct LegacyProxyRowPurge: SQLiteMigrationStep {

    /// Type name as written in `entity_proxy.entity_type` — the Swift type name,
    /// e.g. `"ChatOutboxItem"`.
    private let entityType: String

    /// Namespace whose store owns the rows. The step is a no-op in every other
    /// namespace, since each one is its own SQLite file.
    private let namespace: String

    public init(entityType: String, namespace: String) {
        self.entityType = entityType
        self.namespace = namespace
    }

    // MARK: - MigrationStep

    // Versions carry no meaning here — this is a one-shot cleanup, not a schema
    // revision. Uniqueness comes from `migrationIdentifier`.
    public var fromVersion: Int { 0 }
    public var toVersion: Int { 1 }

    public var description: String {
        "Purge orphaned \(entityType) rows from entity_proxy in \(namespace)"
    }

    // MARK: - SQLiteMigrationStep

    var migrationIdentifier: String {
        "purge_proxy_rows_\(namespace)_\(entityType)"
    }

    func validate(in context: SQLiteMigrationContext) async throws {}

    func perform(in context: SQLiteMigrationContext) async throws {
        try performSync(in: context)
    }

    func rollback(in context: SQLiteMigrationContext) async throws {
        // Nothing to restore: the rows were unreachable before this ran.
    }

    func performSync(in context: SQLiteMigrationContext) throws {
        guard context.namespace == namespace else { return }
        guard try context.tableExists("entity_proxy") else { return }

        try context.db.execute(
            sql: "DELETE FROM entity_proxy WHERE entity_type = ?",
            arguments: [entityType]
        )
    }
}
