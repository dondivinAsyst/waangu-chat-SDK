// MARK: - NetworkKit/Policy/AdaptivePolicyResolver.swift
//
// Calcule DeviceConfiguration en combinant :
//   - DeviceTier (statique, calculé une fois au bootstrap)
//   - PerformanceSnapshot (dynamique, capturé au moment de la résolution)
//   - NetworkSnapshot (dynamique, capturé au moment de la résolution)
//
// isConnectedToNetwork n'est plus dans DeviceConfiguration —
// il est lu directement depuis NetworkMonitor à chaque requête dans APIClient.

import Foundation
import WaanguCoreKit
import WaanguDeviceKit

// MARK: - Protocol

public protocol AdaptivePolicyResolvingProtocol: Sendable {
    func resolve(
        performanceMonitor: any PerformanceMonitorProtocol,
        networkMonitor: any NetworkMonitoringProtocol
    ) async -> DeviceConfiguration
}

// MARK: - AdaptivePolicyResolver

/// Résout la configuration réseau optimale pour le device et les conditions courantes.
///
/// Appelé une seule fois lors de la création de l'APIClient via APIClientFactory.
/// DeviceConfiguration est figée après création — les changements runtime (thermal,
/// network) sont gérés par PerformanceMonitor.criticalEvents() dans NetworkKit.
public final class AdaptivePolicyResolver: AdaptivePolicyResolvingProtocol {

    private let deviceTier: any DeviceTierProtocol

    public init(deviceTier: any DeviceTierProtocol) {
        self.deviceTier = deviceTier
    }

    public func resolve(
        performanceMonitor: any PerformanceMonitorProtocol,
        networkMonitor: any NetworkMonitoringProtocol
    ) async -> DeviceConfiguration {

        var config = await baseConfiguration(for: deviceTier)

        let perfSnapshot    = await performanceMonitor.getSnapshot()
        let networkSnapshot = await networkMonitor.currentSnapshot()

        // MARK: - Réseau indisponible
        guard networkSnapshot.isReachable else {
            config.maxConcurrentRequests = 1
            config.backgroundUpdates     = false
            config.retryProfile          = .none
            return config
        }

        // MARK: - Pression mémoire / CPU
        if perfSnapshot.metrics.memory.isCritical ||
            perfSnapshot.metrics.cpuUsage > 90 {
            config.maxConcurrentRequests = max(1, config.maxConcurrentRequests - 2)
            config.retryProfile          = .conservative
        }

        // MARK: - Batterie faible / Low Power Mode
        if perfSnapshot.metrics.battery.isLow ||
            !perfSnapshot.metrics.battery.isCharging && perfSnapshot.metrics.battery.level < 0.2 {
            config.backgroundUpdates = false
            config.retryProfile      = .conservative
        }

        // MARK: - Throttling thermique
        if perfSnapshot.metrics.thermalState == .serious ||
            perfSnapshot.metrics.thermalState == .critical {
            config.maxConcurrentRequests = min(config.maxConcurrentRequests, 2)
            config.retryProfile          = .conservative
        }

        // MARK: - Réseau contraint ou coûteux (cellulaire, Low Data Mode)
        if networkSnapshot.isExpensive || networkSnapshot.isConstrained {
            config.maxConcurrentRequests = min(config.maxConcurrentRequests, 2)
            config.retryProfile          = .conservative
            config.timeoutMultiplier    *= 1.3
        }

        if networkSnapshot.status == .cellular {
            config.cacheSizeMB       = min(config.cacheSizeMB, 128)
            config.timeoutMultiplier *= 1.2
        }

        // MARK: - Conditions optimales → profil standard
        if await deviceTier.getDeviceTier() == .premium,
           networkSnapshot.isReachable,
           !networkSnapshot.isConstrained,
           !perfSnapshot.metrics.battery.isLow {
            config.retryProfile = .standard
        }

        return config
    }

    // MARK: - Base configuration par tier

    private func baseConfiguration(
        for tier: any DeviceTierProtocol
    ) async -> DeviceConfiguration {
        switch await tier.getDeviceTier() {
        case .premium:
            return DeviceConfiguration(
                maxConcurrentRequests: 6,
                cacheSizeMB: 512,
                backgroundUpdates: true,
                retryProfile: .standard,
                timeoutMultiplier: 1.0,
                minTimeout: 5,
                maxTimeout: 60
            )
        case .midRange:
            return DeviceConfiguration(
                maxConcurrentRequests: 4,
                cacheSizeMB: 256,
                backgroundUpdates: true,
                retryProfile: .standard,
                timeoutMultiplier: 1.2,
                minTimeout: 8,
                maxTimeout: 90
            )
        case .lowEnd:
            return DeviceConfiguration(
                maxConcurrentRequests: 2,
                cacheSizeMB: 128,
                backgroundUpdates: false,
                retryProfile: .conservative,
                timeoutMultiplier: 1.5,
                minTimeout: 10,
                maxTimeout: 120
            )
        }
    }
}
