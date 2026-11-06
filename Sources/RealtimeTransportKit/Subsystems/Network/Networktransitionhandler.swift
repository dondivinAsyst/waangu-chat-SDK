//
//  Networktransitionhandler.swift
//  AppModules
//
//  Created by Asyst on 6/4/26.
//

// MARK: - RealtimeKit/Network/NetworkTransitionHandler.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Détecte les transitions réseau (WiFi ↔ Cellular, perte/retour)
//           et déclenche un reconnect proactif au lieu d'attendre
//           le timeout du heartbeat (15-60 secondes de latence inutile).
//
// CONSOMME NetworkKit — ne recrée pas le monitoring.
//   NetworkMonitoringProtocol est injecté depuis NetworkKit existant.
//
// Design  : Actor pour le thread safety.
//           Observe le stream de snapshots réseau et compare chaque
//           transition avec l'état précédent pour détecter les changements.

import Foundation
import WaanguCoreKit

// MARK: - NetworkTransitionHandler

/// Détecte les changements réseau et notifie le RealtimeClient.
///
/// Différence avec le retry passif du ReconnectionManager :
/// - ReconnectionManager : attend que le transport échoue, puis retente
/// - NetworkTransitionHandler : détecte proactivement le changement
///   et déclenche un reconnect AVANT que le heartbeat timeout
///
/// ```
/// WiFi → Cellular :
///   Sans handler → heartbeat timeout 25s → reconnect
///   Avec handler → détection immédiate   → reconnect
/// ```
actor NetworkTransitionHandler {

    // MARK: - Dependencies

    /// Moniteur réseau existant de NetworkKit — pas recréé ici.
    private let networkMonitor: any NetworkMonitoringProtocol

    // MARK: - State

    /// Dernier snapshot réseau connu.
    private var lastSnapshot: NetworkSnapshot?

    /// Task de monitoring en cours.
    private var monitoringTask: Task<Void, Never>?

    // MARK: - Init

    init(networkMonitor: any NetworkMonitoringProtocol) {
        self.networkMonitor = networkMonitor
    }

    // MARK: - Public API

    /// Démarre la surveillance des transitions réseau.
    ///
    /// - Parameter onTransition: Callback appelé à chaque événement réseau significatif.
    func startMonitoring(
        onTransition: @Sendable @escaping (NetworkTransitionEvent) async -> Void
    ) {
        monitoringTask?.cancel()
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await self.runMonitoringLoop(onTransition: onTransition)
        }
    }

    /// Arrête la surveillance.
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        lastSnapshot = nil
    }

    // MARK: - Private — Monitoring Loop

    private func runMonitoringLoop(
        onTransition: @Sendable @escaping (NetworkTransitionEvent) async -> Void
    ) async {
        // Initialiser avec le snapshot courant.
        lastSnapshot = await networkMonitor.currentSnapshot()

        // Observer les changements via le stream du moniteur.
        for await snapshot in networkMonitor.networkStatusStream() {
            guard !Task.isCancelled else { break }
            await handleSnapshot(snapshot, onTransition: onTransition)
        }
    }

    private func handleSnapshot(
        _ snapshot: NetworkSnapshot,
        onTransition: @Sendable @escaping (NetworkTransitionEvent) async -> Void
    ) async {
        defer { lastSnapshot = snapshot }

        guard let previous = lastSnapshot else {
            lastSnapshot = snapshot
            return
        }

        // Détecter les événements significatifs.
        let event = detectTransition(from: previous, to: snapshot)

        guard let event else { return }

        #if DEBUG
        print("[RealtimeKit] Network transition: \(event)")
        #endif

        await onTransition(event)
    }

    // MARK: - Private — Transition Detection

    private func detectTransition(
        from previous: NetworkSnapshot,
        to current: NetworkSnapshot
    ) -> NetworkTransitionEvent? {

        // 1. Réseau perdu.
        if previous.isReachable && !current.isReachable {
            return .networkLost
        }

        // 2. Réseau retrouvé.
        if !previous.isReachable && current.isReachable {
            return .networkRestored(isExpensive: current.isExpensive)
        }

        // 3. Changement de type (WiFi → Cellular ou inverse).
        if previous.isReachable && current.isReachable,
           previous.status != current.status {
            return .transportChanged(from: previous.status, to: current.status)
        }

        // 4. Passage en Low Data Mode ou réseau coûteux.
        if !previous.isConstrained && current.isConstrained {
            return .becameConstrained
        }

        if previous.isConstrained && !current.isConstrained {
            return .becameUnconstrained
        }

        return nil
    }
}

// MARK: - NetworkTransitionEvent

/// Événement de transition réseau émis par le handler.
enum NetworkTransitionEvent: Sendable, CustomStringConvertible {

    /// Le réseau est devenu indisponible (WiFi + Cellular perdus).
    case networkLost

    /// Le réseau est revenu.
    case networkRestored(isExpensive: Bool)

    /// Le type de transport a changé (ex: WiFi → Cellular).
    case transportChanged(from: NetworkStatus, to: NetworkStatus)

    /// Le réseau est passé en mode contraint (Low Data Mode, etc.).
    case becameConstrained

    /// Le réseau n'est plus contraint.
    case becameUnconstrained

    var description: String {
        switch self {
        case .networkLost:
            return "Network lost"
        case .networkRestored(let expensive):
            return "Network restored (expensive: \(expensive))"
        case .transportChanged(let from, let to):
            return "Transport: \(from) → \(to)"
        case .becameConstrained:
            return "Network became constrained"
        case .becameUnconstrained:
            return "Network unconstrained"
        }
    }

    /// `true` si cet événement devrait déclencher un reconnect.
    var shouldReconnect: Bool {
        switch self {
        case .networkRestored, .transportChanged:
            return true
        case .networkLost, .becameConstrained, .becameUnconstrained:
            return false
        }
    }

    /// `true` si cet événement devrait activer la compression.
    var shouldEnableCompression: Bool {
        switch self {
        case .transportChanged(_, let to) where to == .cellular:
            return true
        case .becameConstrained:
            return true
        default:
            return false
        }
    }
}

// MARK: - NetworkMonitoringProtocol Extension

extension NetworkMonitoringProtocol {
    /// Stream des snapshots réseau — à implémenter dans NetworkKit.
    /// Placeholder : émet toutes les 5 secondes si le monitoring n'est
    /// pas en streaming natif.
    func networkStatusStream() -> AsyncStream<NetworkSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let snapshot = await self.currentSnapshot()
                    continuation.yield(snapshot)
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
