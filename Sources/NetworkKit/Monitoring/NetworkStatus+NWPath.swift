// MARK: - NetworkKit/Monitoring/NetworkStatus+NWPath.swift
//
// Extension de NetworkStatus (défini dans CoreKit) avec init(path: NWPath).
// Network.framework requis — c'est pourquoi cette extension vit dans NetworkKit.
//
// CoreKit définit NetworkStatus avec tous les cases (wifi, cellular, wiredEthernet, other, disconnected).
// NetworkKit ajoute uniquement init(path: NWPath) — sans redéfinir le type.

import Foundation
import Network
import WaanguCoreKit

// MARK: - NetworkStatus enrichi

/// Extension de NetworkStatus avec les cas interface-spécifiques.
/// Ces cases remplacent `.connected` dans NetworkKit — plus granulaires.
extension NetworkStatus {

    /// Initialisation depuis NWPath — Network.framework requis.
    /// Utilisé exclusivement par NetworkMonitor.
    init(path: NWPath) {
        guard path.status == .satisfied else {
            self = .disconnected
            return
        }
        if path.usesInterfaceType(.wifi) {
            self = .wifi
        } else if path.usesInterfaceType(.cellular) {
            self = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            self = .wiredEthernet
        } else {
            self = .other
        }
    }
}
