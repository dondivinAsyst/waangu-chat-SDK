//
//  DeviceTier.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

// Calcul et cache du tier hardware du device.
// DeviceTierSnapshot et DeviceTierProtocol sont définis dans CoreKit.

import WaanguCoreKit
import Foundation

/// Calcule et met en cache le tier hardware du device.
///
/// Score de calcul :
///   CPU     : processorCount × 10 pts
///   RAM     : physicalMemoryGB × 10 pts
///   Storage : 10–30 pts selon la capacité totale
///   Max     : 100 pts
///
///   premium  ≥ 80 pts
///   midRange ≥ 50 pts
///   lowEnd   < 50 pts
public actor DeviceTier: DeviceTierProtocol {

    private let deviceInfoSnapshot: DeviceInfoSnapshot
    private let logger: AppLogger
    private var cachedTier: DeviceTierSnapshot?

    public init(deviceInfoSnapshot: DeviceInfoSnapshot, logger: AppLogger) {
        self.deviceInfoSnapshot = deviceInfoSnapshot
        self.logger = logger
    }

    // MARK: - Public API

    public func getDeviceTier() async -> DeviceTierSnapshot {
        if let cached = cachedTier { return cached }
        let tier = calculateTier()
        cachedTier = tier
        await logger.log("Device tier resolved: \(tier)", level: .info)
        return tier
    }

    // MARK: - Calculation

    private func calculateTier() -> DeviceTierSnapshot {
        let score = calculateScore()
        switch score {
        case 80...100: return .premium
        case 50..<80:  return .midRange
        default:       return .lowEnd
        }
    }

    private func calculateScore() -> Double {
        var score = 0.0
        score += Double(deviceInfoSnapshot.processorCount) * 10.0
        score += Double(deviceInfoSnapshot.physicalMemoryMB) / 1024.0 * 10.0
        score += storageScore()
        return min(100.0, score)
    }

    private func storageScore() -> Double {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ) else { return 10 }

        let totalGB = ((attributes[.systemSize] as? NSNumber)?.doubleValue ?? 0) / 1_000_000_000

        switch totalGB {
        case 256...:    return 30
        case 128..<256: return 25
        case 64..<128:  return 20
        case 32..<64:   return 15
        default:        return 10
        }
    }
}
