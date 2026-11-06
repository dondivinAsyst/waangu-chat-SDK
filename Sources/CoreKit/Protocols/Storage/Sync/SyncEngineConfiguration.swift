//
//  SyncEngineConfiguration.swift
//  AppModules
//
//  CoreKit/Sources/Sync
//

import Foundation

// MARK: - Sync Engine Configuration

/// Configuration du sync engine, passée lors de la construction
/// dans le `DependencyContainer`.
///
/// Séparée de `OutboxConfiguration` qui est encapsulée dans le flush manager.
/// Cette config ne concerne que la phase pull (descendante).
public struct SyncEngineConfiguration: Sendable {

    /// Nombre d'événements par page lors du pull paginé.
    public let pullPageSize: Int

    /// Délai entre chaque page pour ne pas saturer le réseau
    /// (surtout sur 3G/entrée de gamme).
    public let interPageDelay: TimeInterval

    public static let `default` = SyncEngineConfiguration(
        pullPageSize: 50,
        interPageDelay: 0.3
    )

    /// Config adaptée aux conditions réseau difficiles.
    public static let conservative = SyncEngineConfiguration(
        pullPageSize: 20,
        interPageDelay: 1.0
    )

    /// Config pour les features critiques (wallet).
    public static let aggressive = SyncEngineConfiguration(
        pullPageSize: 100,
        interPageDelay: 0.1
    )

    public init(pullPageSize: Int, interPageDelay: TimeInterval) {
        self.pullPageSize = pullPageSize
        self.interPageDelay = interPageDelay
    }
}

