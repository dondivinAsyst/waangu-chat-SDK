// MARK: - CoreKit/Protocols/PerformanceMonitorProtocol.swift
//
// Protocole et types de données de performance.
// Zéro UIKit ici — CoreKit ne doit pas dépendre de UIKit.
//
// Règle :
// - Les structs ici sont de purs conteneurs de données (Sendable, no methods)
// - Les méthodes de capture (.current(), cpuUsage()...) vivent dans DeviceKit
//   car elles dépendent de UIDevice, Mach APIs etc.
//
// Extension dans DeviceKit :
//   extension BatteryStatus { static func current() -> BatteryStatus { UIDevice... } }
//   extension MemorySnapshot { static func current() -> MemorySnapshot { mach_... } }

import Foundation

// MARK: - MemorySnapshot

/// Conteneur de données mémoire — pur, sans logique de capture.
public struct MemorySnapshot: Sendable {
    public let usedMB: Double
    public let availableMB: Double
    public let totalMB: Double

    public var usageRatio: Double {
        guard totalMB > 0 else { return 0 }
        return usedMB / totalMB
    }

    /// `true` si l'usage mémoire dépasse 70% — seuil d'avertissement.
    public var isWarning: Bool { usageRatio > 0.70 }

    /// `true` si l'usage mémoire dépasse 85% — seuil critique.
    /// Utilisé par AdaptivePolicyResolver pour réduire la concurrence réseau.
    public var isCritical: Bool { usageRatio > 0.85 }

    public init(usedMB: Double, availableMB: Double, totalMB: Double) {
        self.usedMB = usedMB
        self.availableMB = availableMB
        self.totalMB = totalMB
    }
}

// MARK: - BatteryStatus

/// Conteneur de données batterie — pur, sans logique de capture UIDevice.
/// La méthode `current()` est définie dans DeviceKit via extension.
public struct BatteryStatus: Sendable {
    public let level: Float        // 0.0 → 1.0, -1.0 si indéterminé
    public let isCharging: Bool
    public let isLow: Bool         // true si level in [0, 0.20[

    public init(level: Float, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
        self.isLow = level >= 0 && level < 0.20
    }
}

// MARK: - PerformanceMetrics

/// Métriques agrégées — conteneur pur, sans logique de capture.
public struct PerformanceMetrics: Sendable {
    public let memory: MemorySnapshot
    public let cpuUsage: Double
    public let battery: BatteryStatus
    public let thermalState: ProcessInfo.ThermalState

    public init(
        memory: MemorySnapshot,
        cpuUsage: Double,
        battery: BatteryStatus,
        thermalState: ProcessInfo.ThermalState
    ) {
        self.memory = memory
        self.cpuUsage = cpuUsage
        self.battery = battery
        self.thermalState = thermalState
    }

    /// `true` si le système est sous pression.
    /// Utilisé par APIClient pour adapter sa config runtime.
    public var isUnderPressure: Bool {
        thermalState == .serious ||
        thermalState == .critical ||
        memory.usageRatio > 0.85 ||
        battery.isLow
    }
}

// MARK: - PerformanceSnapshot

/// Snapshot horodaté — conteneur pur.
public struct PerformanceSnapshot: Sendable {
    public let timestamp: Date
    public let metrics: PerformanceMetrics

    public init(timestamp: Date, metrics: PerformanceMetrics) {
        self.timestamp = timestamp
        self.metrics = metrics
    }
}

// MARK: - PerformanceEventType

public enum PerformanceEventType: Sendable {
    /// Thermal state dégradé — iOS throttle le CPU et le réseau.
    case thermalWarning(state: ProcessInfo.ThermalState)
    /// Low Power Mode activé ou désactivé.
    case lowPowerModeChanged(isEnabled: Bool)
}

// MARK: - PerformanceEvent

public struct PerformanceEvent: Sendable {
    public let type: PerformanceEventType
    public let timestamp: Date
    public let snapshot: PerformanceSnapshot

    public init(
        type: PerformanceEventType,
        snapshot: PerformanceSnapshot,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.snapshot = snapshot
        self.timestamp = timestamp
    }
}

// MARK: - PerformanceMonitorProtocol

/// Contrat de monitoring de performance système.
/// L'implémentation concrète (PerformanceMonitor) vit dans DeviceKit.
public protocol PerformanceMonitorProtocol: Sendable {
    /// Capture fraîche à chaque appel — ne pas appeler en boucle serrée.
    func getSnapshot() async -> PerformanceSnapshot

    /// Stream d'événements critiques (thermal warning, low power mode).
    /// Seules les implémentations réelles émettent ; les mocks peuvent retourner un stream vide.
    func criticalEvents() -> AsyncStream<PerformanceEvent>
}
