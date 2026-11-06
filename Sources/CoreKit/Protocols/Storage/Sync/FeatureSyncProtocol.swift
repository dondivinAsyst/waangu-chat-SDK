//
//  FeatureSyncProtocol.swift
//  AppModules
//
//  CoreKit/Sources/Sync
//

import Foundation

// MARK: - Sync Priority

/// Priorité de synchro d'une feature.
/// Le SyncCoordinator trie par rawValue croissant (critical en premier).
public enum SyncPriority: Int, Sendable, Comparable {
    case critical = 0   // Wallet (solde, transactions)
    case high     = 1   // Chat (messages offline)
    case normal   = 2   // Ride (trajets en cours)
    case low      = 3   // Marketplace, catalogue
    case deferred = 4   // Historique, analytics

    public static func < (lhs: SyncPriority, rhs: SyncPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Feature Sync Protocol

/// Contrat qu'une feature expose pour participer à la synchro
/// orchestrée par `SyncCoordinator`.
///
/// Le coordinator ne fait que :
///   1. Appeler `flushOutbox()` puis `pullMissedEvents()` par priorité
///   2. Adapter le pacing entre les features
///   3. Annuler via `stopSync()` au logout ou background
public protocol FeatureSyncProtocol: Sendable {

    /// Nom lisible pour le logging (ex: "wallet", "chat", "ride").
    var featureName: String { get }

    /// Priorité de cette feature dans l'ordre de synchro.
    var syncPriority: SyncPriority { get }

    /// Phase montante : envoie les actions pending du client vers le serveur.
    func flushOutbox() async

    /// Phase descendante : récupère les événements manqués depuis le serveur.
    func pullMissedEvents() async

    /// Annule toute opération de sync en cours pour cette feature.
    func stopSync() async

    /// Vrai quand le pull bute depuis plusieurs passages sur le même événement
    /// (`SyncState.isDegraded`). Faux par défaut : une feature qui ne le suit pas n'est jamais
    /// signalée dégradée.
    func isDegraded() async -> Bool
}

public extension FeatureSyncProtocol {
    func isDegraded() async -> Bool { false }
}


