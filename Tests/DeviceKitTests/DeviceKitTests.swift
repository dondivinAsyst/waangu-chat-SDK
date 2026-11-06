import Testing
@testable import WaanguDeviceKit
@testable import WaanguCoreKit

@Suite("DeviceKit")
struct DeviceKitTests {

    @Test("MemorySnapshot usage ratio calculation")
    func memoryUsageRatio() {
        let snapshot = MemorySnapshot(usedMB: 700, availableMB: 300, totalMB: 1000)
        #expect(snapshot.usageRatio == 0.7)

        // Le seuil se *dépasse* (doc de `isWarning` / `isCritical`) : 70 % pile
        // n'avertit pas encore (B43 — le test attendait l'inverse).
        #expect(!snapshot.isWarning)
        #expect(MemorySnapshot(usedMB: 710, availableMB: 290, totalMB: 1000).isWarning)
        #expect(!MemorySnapshot(usedMB: 850, availableMB: 150, totalMB: 1000).isCritical)
        #expect(MemorySnapshot(usedMB: 860, availableMB: 140, totalMB: 1000).isCritical)
    }

    @Test("BatteryStatus low detection")
    func batteryLow() {
        let low = BatteryStatus(level: 0.15, isCharging: false)
        #expect(low.isLow)

        let ok = BatteryStatus(level: 0.50, isCharging: false)
        #expect(!ok.isLow)
    }
}
