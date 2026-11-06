//
//  PerformanceMonitor.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

// MARK: - DeviceKit/Performance/PerformanceMonitor.swift
//
// Monitoring de performance — deux patterns complémentaires :
//
// PULL  → getSnapshot()
//         CPU, mémoire, batterie, thermal — lecture ponctuelle à la demande.
//         Appelé par APIClient avant chaque requête pour adapter sa config runtime.
//         Ne pas appeler en boucle serrée.
//
// PUSH  → criticalEvents() → AsyncStream<PerformanceEvent>
//         Uniquement thermal (.serious/.critical) + low power mode.
//         iOS émet ces notifications au moment exact du changement —
//         un poll approximerait à coût batterie ce qu'iOS donne gratuitement.
//
// Batterie, CPU, mémoire → pull pur via getSnapshot().

import WaanguCoreKit
import UIKit
import Foundation

// MARK: - PerformanceMonitor

public actor PerformanceMonitor: PerformanceMonitorProtocol {

    // MARK: - Singleton
    public static let shared = PerformanceMonitor()

    // MARK: - Stream state
    private var continuations: [UUID: AsyncStream<PerformanceEvent>.Continuation] = [:]
    private var observationTask: Task<Void, Never>?

    // MARK: - Init
    private init() {}

    /// Active le monitoring batterie — doit être appelé depuis le MainActor
    /// avant tout appel à `BatteryStatus.current()`.
    /// Typiquement appelé une fois au bootstrap de l'app.
    public func enableBatteryMonitoring() async {
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
    }

    // MARK: - PULL : getSnapshot()

    /// Snapshot ponctuel — CPU, mémoire, batterie, thermal.
    ///
    /// Appeler avant toute opération lourde :
    /// - APIClient : avant chaque requête pour adapter retry/timeout
    /// - FileTransfer : avant de démarrer un upload
    ///
    /// Ne pas appeler en boucle serrée (< 500ms entre deux appels).
    public func getSnapshot() async -> PerformanceSnapshot {
        PerformanceSnapshot(
            timestamp: Date(),
            metrics: PerformanceMetrics(
                memory: MemorySnapshot.current(),
                cpuUsage: cpuUsage(),
                battery: BatteryStatus.current(),
                thermalState: ProcessInfo.processInfo.thermalState
            )
        )
    }

    // MARK: - PUSH : criticalEvents()

    /// Stream d'événements critiques système.
    ///
    /// Émet sur :
    /// - `.thermalWarning` — thermal state .serious ou .critical
    /// - `.lowPowerModeChanged` — activation / désactivation Low Power Mode
    ///
    /// Auto-gestion : l'observation NotificationCenter démarre au premier abonné
    /// et s'arrête automatiquement quand plus personne n'écoute.
    ///
    /// Usage typique dans NetworkKit/AdaptivePolicyResolver :
    /// ```swift
    /// for await event in await PerformanceMonitor.shared.criticalEvents() {
    ///     switch event.type {
    ///     case .thermalWarning:
    ///         await adaptRetryPolicy(to: .conservative)
    ///     case .lowPowerModeChanged(let isEnabled) where isEnabled:
    ///         await reduceNetworkLoad()
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    public nonisolated func criticalEvents() -> AsyncStream<PerformanceEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task {
                await self._register(id: id, continuation: continuation)
                await self._startObservingIfNeeded()
            }
            continuation.onTermination = { _ in
                Task { await self._unregister(id: id) }
            }
        }
    }

    // MARK: - CPU (Mach API)

    private func cpuUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t()

        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else { return 0 }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: threads),
                vm_size_t(threadCount * UInt32(MemoryLayout<thread_t>.size))
            )
        }

        return (0..<Int(threadCount)).reduce(0.0) { total, i in
            var info  = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            guard kr == KERN_SUCCESS, (info.flags & TH_FLAGS_IDLE) == 0 else { return total }
            return total + Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }
    }

    // MARK: - NotificationCenter observation (privée)

    private func _startObservingIfNeeded() {
        guard observationTask == nil else { return }

        observationTask = Task { [weak self] in
            guard let self else { return }

            await withTaskGroup(of: Void.self) { group in

                // Thermal state — .serious et .critical uniquement
                group.addTask {
                    for await _ in NotificationCenter.default.notifications(
                        named: ProcessInfo.thermalStateDidChangeNotification
                    ) {
                        let state = ProcessInfo.processInfo.thermalState
                        guard state == .serious || state == .critical else { continue }
                        await self._emit(.thermalWarning(state: state))
                    }
                }

                // Low Power Mode — activation et désactivation
                group.addTask {
                    for await _ in NotificationCenter.default.notifications(
                        named: .NSProcessInfoPowerStateDidChange
                    ) {
                        let isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                        await self._emit(.lowPowerModeChanged(isEnabled: isEnabled))
                    }
                }
            }
        }
    }

    private func _emit(_ type: PerformanceEventType) async {
        let snapshot = await getSnapshot()
        let event = PerformanceEvent(type: type, snapshot: snapshot)
        continuations.values.forEach { $0.yield(event) }
    }

    private func _register(
        id: UUID,
        continuation: AsyncStream<PerformanceEvent>.Continuation
    ) {
        continuations[id] = continuation
    }

    private func _unregister(id: UUID) {
        continuations[id] = nil
        // Arrêter l'observation quand plus aucun abonné — zéro overhead au repos
        if continuations.isEmpty {
            observationTask?.cancel()
            observationTask = nil
        }
    }
}
