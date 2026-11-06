//
//  OutboxConfiguration.swift
//  AppModules
//
//  Created by Asyst on 6/19/26.
//


// MARK: - OutboxConfiguration.swift
//
// Module  : CoreKit
// Path    : CoreKit/Sources/Sync
//
// Configuration du flush manager d'outbox.
// Séparée de SyncEngineConfiguration qui ne concerne que le pull.
// Celle-ci concerne le push (outbox → serveur).

import Foundation

// MARK: - Outbox Configuration

/// Configuration du comportement du flush d'outbox.
///
/// Trois presets adaptés aux différents niveaux de criticité :
///   `.default`    → chat, ride (batch 30, 5 retries)
///   `.critical`   → wallet (batch 10, 10 retries, nettoyage lent)
///   `.relaxed`    → marketplace, reactions (batch 50, 3 retries)
///
/// ```swift
/// // DependencyContainer
/// let chatFlushManager = OutboxFlushManager(
///     outbox: chatOutbox,
///     config: .default,
///     flush: { ... }
/// )
/// let walletFlushManager = OutboxFlushManager(
///     outbox: walletOutbox,
///     config: .critical,     // ← plus prudent pour les transactions
///     flush: { ... }
/// )
/// ```
public struct OutboxConfiguration: Sendable {

    /// Nombre d'items par batch HTTP.
    /// Plus petit = requêtes plus légères (3G), plus de requêtes.
    /// Plus grand = moins de requêtes, body plus lourd.
    public let batchSize: Int

    /// Nombre maximum de retries avant de marquer un item comme `.failed`.
    /// Au-delà, l'item n'est plus repris automatiquement.
    public let maxRetries: Int

    /// Durée (secondes) après laquelle un item en `.syncing` est considéré bloqué.
    /// Un item bloqué est remis en `.pending` pour être re-traité.
    /// Couvre le cas où l'app a crashé entre le POST et le traitement de la réponse.
    public let stuckTimeout: TimeInterval

    /// Durée de rétention des items `.synced` avant suppression définitive.
    /// Garder un historique permet le debugging post-mortem.
    public let syncedRetention: TimeInterval

    /// Délai entre chaque batch pour ne pas saturer le réseau.
    /// Critique sur les réseaux 3G africains.
    public let interBatchDelay: TimeInterval

    // MARK: - Presets

    /// Chat, ride — compromis standard.
    public static let `default` = OutboxConfiguration(
        batchSize: 30,
        maxRetries: 5,
        stuckTimeout: 120,
        syncedRetention: 86400,       // 24h
        interBatchDelay: 0.5
    )

    /// Wallet — transactions financières, tolérance zéro.
    public static let critical = OutboxConfiguration(
        batchSize: 10,
        maxRetries: 10,
        stuckTimeout: 60,
        syncedRetention: 172800,      // 48h
        interBatchDelay: 0.3
    )

    /// Marketplace, reactions — non-critique.
    public static let relaxed = OutboxConfiguration(
        batchSize: 50,
        maxRetries: 3,
        stuckTimeout: 300,
        syncedRetention: 3600,        // 1h
        interBatchDelay: 1.0
    )

    // MARK: - Init

    public init(
        batchSize: Int,
        maxRetries: Int,
        stuckTimeout: TimeInterval,
        syncedRetention: TimeInterval,
        interBatchDelay: TimeInterval
    ) {
        self.batchSize = batchSize
        self.maxRetries = maxRetries
        self.stuckTimeout = stuckTimeout
        self.syncedRetention = syncedRetention
        self.interBatchDelay = interBatchDelay
    }
}
