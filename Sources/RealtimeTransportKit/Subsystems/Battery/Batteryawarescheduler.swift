//
//  Batteryawarescheduler.swift
//  AppModules
//
//  Created by Asyst on 6/4/26.
//

// MARK: - RealtimeKit/Battery/BatteryAwareScheduler.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Adapte l'intervalle de heartbeat selon :
//           - L'état foreground/background de l'app
//           - Le niveau de batterie et le mode économie d'énergie
//           - L'état thermique du device
//           - Le type de réseau (WiFi vs Cellular)
//
// CONSOMME PerformanceMonitorProtocol de NetworkKit — pas recréé.
//
// Design  : Actor. Surveille les notifications système et ajuste
//           dynamiquement le heartbeat via le transport.

import Foundation
import WaanguCoreKit
import UIKit


// MARK: - BatteryAwareScheduler

/// Ajuste le heartbeat du transport selon les conditions du device.
///
/// Foreground, WiFi, batterie ok  → 15s (haute réactivité)
/// Background                      → 60s (économie batterie)
/// Low Power Mode                  → 120s (économie agressive)
/// Thermique critique              → 120s (réduire l'activité)
/// Cellular                        → 30s (compromis data/batterie)
actor BatteryAwareScheduler {

    // MARK: - Dependencies

    private let performanceMonitor: any PerformanceMonitorProtocol
    private let transport: any RealtimeTransport

    // MARK: - Configuration

    private let intervals: HeartbeatIntervals

    // MARK: - State

    private var schedulerTask: Task<Void, Never>?
    private var currentInterval: TimeInterval

    // MARK: - Init

    init(
        performanceMonitor: any PerformanceMonitorProtocol,
        transport: any RealtimeTransport,
        intervals: HeartbeatIntervals = .default
    ) {
        self.performanceMonitor = performanceMonitor
        self.transport = transport
        self.intervals = intervals
        self.currentInterval = intervals.foreground
    }

    // MARK: - Public API

    /// Démarre la surveillance et l'adaptation automatique du heartbeat.
    func startAdapting() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            guard let self else { return }
            await self.runAdaptationLoop()
        }
    }

    /// Arrête la surveillance.
    func stopAdapting() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    /// Notifie que l'app est passée en foreground.
    func appDidEnterForeground() async {
        await applyInterval(await resolveOptimalInterval(background: false))
    }

    /// Notifie que l'app est passée en background.
    func appDidEnterBackground() async {
        await applyInterval(intervals.background)
    }

    // MARK: - Private — Adaptation Loop

    private func runAdaptationLoop() async {
        // Observer les conditions toutes les 30 secondes.
        while !Task.isCancelled {
            let isBackground = await isAppInBackground()
            let optimal = await resolveOptimalInterval(background: isBackground)

            if abs(optimal - currentInterval) > 1.0 {
                await applyInterval(optimal)
            }

            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
    }

    // MARK: - Private — Interval Resolution

    private func resolveOptimalInterval(background: Bool) async -> TimeInterval {
        if background {
            return intervals.background
        }

        let snapshot = await performanceMonitor.getSnapshot()
        let metrics = snapshot.metrics

        // Low Power Mode ou batterie très faible → aggressif.
        if metrics.battery.isLow || ProcessInfo.processInfo.isLowPowerModeEnabled {
            return intervals.lowPower
        }

        // Thermique critique → réduire.
        if metrics.thermalState == .critical || metrics.thermalState == .serious {
            return intervals.thermalThrottled
        }

        return intervals.foreground
    }

    private func applyInterval(_ interval: TimeInterval) async {
        guard interval != currentInterval else { return }
        currentInterval = interval
        await transport.updateHeartbeatInterval(interval)

        #if DEBUG
        print("[RealtimeKit] Heartbeat interval → \(Int(interval))s")
        #endif
    }

    private func isAppInBackground() async -> Bool {
        #if canImport(UIKit)
        return await MainActor.run {
            UIApplication.shared.applicationState == .background
        }
        #else
        return false
        #endif
    }
}

// MARK: - HeartbeatIntervals

/// Intervalles de heartbeat pour chaque condition.
struct HeartbeatIntervals: Sendable {

    /// App en foreground, conditions normales.
    let foreground: TimeInterval

    /// App en background.
    let background: TimeInterval

    /// Low Power Mode ou batterie critique.
    let lowPower: TimeInterval

    /// Throttle thermique.
    let thermalThrottled: TimeInterval

    static let `default` = HeartbeatIntervals(
        foreground: 15,
        background: 60,
        lowPower: 120,
        thermalThrottled: 90
    )

    /// Pour les features critiques (ride tracking actif).
    static let aggressive = HeartbeatIntervals(
        foreground: 10,
        background: 30,
        lowPower: 60,
        thermalThrottled: 45
    )
}
