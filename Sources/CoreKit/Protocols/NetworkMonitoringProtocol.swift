// MARK: - CoreKit/Protocols/NetworkMonitoringProtocol.swift
//
// Contrat public du monitoring réseau.
// L'implémentation concrète (NetworkMonitor) vit dans NetworkKit.
//
// NetworkStatus contient tous les cases interface-spécifiques ici dans CoreKit.
// NetworkKit ajoute uniquement init(path: NWPath) via extension —
// sans redéfinir le type.

import Foundation

// MARK: - NetworkStatus

/// Statut de connexion réseau avec type d'interface.
///
/// Tous les cases sont définis ici dans CoreKit.
/// NetworkKit ajoute init(path: NWPath) via extension (Network.framework requis).
public enum NetworkStatus: Equatable, Sendable {
    case wifi
    case cellular
    case wiredEthernet
    case other
    case disconnected

    /// Initialisation simple depuis un booléen — utilisée hors NetworkKit
    /// (tests, mocks, previews) sans dépendance sur Network.framework.
    public init(isReachable: Bool) {
        self = isReachable ? .wifi : .disconnected
    }

    /// `true` si le réseau est accessible quelle que soit l'interface.
    public var isReachable: Bool {
        self != .disconnected
    }
}

// MARK: - NetworkSnapshot

/// Snapshot de l'état réseau à un instant donné.
/// Créé par NetworkMonitor (NetworkKit) et consommé partout via le protocole.
public struct NetworkSnapshot: Sendable {

    public let timestamp: Date
    public let status: NetworkStatus
    public let isExpensive: Bool        // connexion cellulaire ou hotspot
    public let isConstrained: Bool      // Low Data Mode activé
    public let isReachable: Bool

    public init(
        timestamp: Date,
        status: NetworkStatus,
        isExpensive: Bool,
        isConstrained: Bool,
        isReachable: Bool
    ) {
        self.timestamp = timestamp
        self.status = status
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.isReachable = isReachable
    }

    /// `true` si le réseau est accessible.
    /// On considère connecté même en Low Data Mode —
    /// AdaptivePolicyResolver réduit la charge dans ce cas.
    public var isConnected: Bool { isReachable }
}

// MARK: - NetworkMonitoringProtocol

/// Contrat public du monitoring réseau.
/// Toujours injecter ce protocole — jamais `NetworkMonitor` directement.
public protocol NetworkMonitoringProtocol: Sendable {

    /// Snapshot courant de l'état réseau — lu en temps réel.
    func currentSnapshot() async -> NetworkSnapshot

    /// `true` si le réseau est actuellement accessible.
    var isConnected: Bool { get async }
}

/// Extension par défaut — évite la duplication dans chaque implémentation.
public extension NetworkMonitoringProtocol {
    var isConnected: Bool {
        get async { await currentSnapshot().isReachable }
    }
}
