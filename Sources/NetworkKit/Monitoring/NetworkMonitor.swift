//
//  NetworkMonitor.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

// Implémentation concrète de NetworkMonitoringProtocol (défini dans CoreKit).
// Utilise NWPathMonitor (Network.framework) — c'est pourquoi elle vit dans NetworkKit.
// NetworkStatus.init(path:) est défini dans NetworkStatus+NWPath.swift (même module).

import Foundation
import Network
import WaanguCoreKit

public actor NetworkMonitor: NetworkMonitoringProtocol {

    public static let shared = NetworkMonitor()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.waangu.network.monitor")
    private var latestSnapshot: NetworkSnapshot

    private init() {
        self.monitor = NWPathMonitor()

        let initialPath = monitor.currentPath
        self.latestSnapshot = NetworkSnapshot(
            timestamp: Date(),
            status: NetworkStatus(path: initialPath),
            isExpensive: initialPath.isExpensive,
            isConstrained: initialPath.isConstrained,
            isReachable: initialPath.status == .satisfied
        )

        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.updateSnapshot(with: path) }
        }

        monitor.start(queue: queue)
    }

    private func updateSnapshot(with path: NWPath) {
        latestSnapshot = NetworkSnapshot(
            timestamp: Date(),
            status: NetworkStatus(path: path),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            isReachable: path.status == .satisfied
        )
    }

    public func currentSnapshot() async -> NetworkSnapshot {
        latestSnapshot
    }
}
