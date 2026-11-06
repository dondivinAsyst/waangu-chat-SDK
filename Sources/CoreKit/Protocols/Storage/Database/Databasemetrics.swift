//
//  Databasemetrics.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : CoreKit                                            │
// │  FICHIER : Database/DatabaseMetrics.swift                    │
// │                                                              │
// │  Contrats d'observabilité de la couche base de données.      │
// │  Indépendants de l'engine : les métriques ont la même forme  │
// │  que l'engine soit CoreData, SwiftData, Realm ou SQLite.     │
// └──────────────────────────────────────────────────────────────┘

import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseOperation
// ─────────────────────────────────────────────────────────────

/// Opération qui a produit les métriques.
public enum DatabaseOperation: String, Sendable, CaseIterable {
    case save
    case saveAll
    case fetch
    case fetchOne
    case count
    case delete
    case deleteAll
    case transaction
    case observe
    case clearAll
}

// ─────────────────────────────────────────────────────────────
// MARK: QueryMetrics
// ─────────────────────────────────────────────────────────────

/// Résultat d'instrumentation d'une opération.
public struct QueryMetrics: Sendable {
    public let id: UUID
    public let namespace: String
    public let operation: DatabaseOperation
    public let duration: Duration
    public let durationMs: Int       
    public let rowCount: Int
    public let isSlowQuery: Bool
    public let timestamp: Date

    public init(
        namespace: String,
        operation: DatabaseOperation,
        duration: Duration,
        rowCount: Int,
        slowThreshold: Duration
    ) {
        self.id          = UUID()
        self.namespace   = namespace
        self.operation   = operation
        self.duration    = duration
        self.durationMs  = Int(
            duration.components.seconds * 1_000
            + duration.components.attoseconds / 1_000_000_000_000_000
        )
        self.rowCount    = rowCount
        self.isSlowQuery = duration > slowThreshold
        self.timestamp   = Date()
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseMetricsDelegate
// ─────────────────────────────────────────────────────────────

/// Branché depuis le App Target sur Firebase, Datadog, Sentry…
/// StorageKit appelle ce delegate après chaque opération.
/// Le App Target ne reçoit que des types CoreKit — jamais de détails engine.
public protocol DatabaseMetricsDelegate: AnyObject, Sendable {

    /// Appelé après chaque opération réussie.
    func database(didExecute metrics: QueryMetrics)

    /// Appelé après chaque erreur.
    func database(
        didFailWith error: DatabaseError,
        operation: DatabaseOperation,
        namespace: String
    )

    /// Appelé après chaque migration réussie.
    func database(
        didMigrate namespace: String,
        fromVersion: Int,
        toVersion: Int,
        duration: Duration
    )
}

// Implémentations par défaut : le delegate n'est pas obligé de tout implémenter.
public extension DatabaseMetricsDelegate {
    func database(
        didFailWith error: DatabaseError,
        operation: DatabaseOperation,
        namespace: String
    ) {}

    func database(
        didMigrate namespace: String,
        fromVersion: Int,
        toVersion: Int,
        duration: Duration
    ) {}
}
