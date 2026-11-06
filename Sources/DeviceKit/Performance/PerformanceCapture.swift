//
//  PerformanceCapture.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

// MARK: - DeviceKit/Performance/PerformanceCapture.swift
//
// Extensions de capture sur les types de données définis dans CoreKit.
//
// Principe de séparation :
//   CoreKit  → types purs (BatteryStatus, MemorySnapshot) — structs Sendable sans UIKit
//   DeviceKit → méthodes current() qui capturent via UIDevice et Mach APIs
//
// Cette séparation permet aux features de recevoir BatteryStatus/MemorySnapshot
// via FeatureDependencies sans dépendre de UIKit ou de Mach APIs.
import WaanguCoreKit
import UIKit
import Foundation

// MARK: - BatteryStatus + current()

public extension BatteryStatus {

    /// Capture l'état batterie courant depuis UIDevice.
    ///
    /// Prérequis : `UIDevice.current.isBatteryMonitoringEnabled = true`
    /// Activé dans `PerformanceMonitor.init()` — ne pas appeler
    /// avant le bootstrap de PerformanceMonitor.
    static func current() -> BatteryStatus {
        let device = UIDevice.current
        return BatteryStatus(
            level: device.batteryLevel,
            isCharging: device.batteryState == .charging
                     || device.batteryState == .full
        )
    }
}

// MARK: - MemorySnapshot + current()

public extension MemorySnapshot {

    /// Capture l'usage mémoire courant via Mach task_info.
    static func current() -> MemorySnapshot {
        let used  = currentUsedMemoryMB()
        let total = totalMemoryMB()
        return MemorySnapshot(
            usedMB: used,
            availableMB: max(0, total - used),
            totalMB: total
        )
    }

    private static func currentUsedMemoryMB() -> Double {
        var info  = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576 // 1024 * 1024
    }

    private static func totalMemoryMB() -> Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576
    }
}
