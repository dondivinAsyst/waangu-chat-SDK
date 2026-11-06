//
//  DeviceCapabilities.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

// Capacités hardware agrégées dérivées du DeviceTier.
// Utilisées par NetworkKit (AdaptivePolicyResolver) pour calibrer
// la config runtime d'APIClient.

import Foundation

public struct DeviceCapabilities: Sendable {

    public let maxMemoryMB: Int
    public let cpuScore: Int
    public let supportsAdvancedGraphics: Bool

    public init(maxMemoryMB: Int, cpuScore: Int, supportsAdvancedGraphics: Bool) {
        self.maxMemoryMB = maxMemoryMB
        self.cpuScore = cpuScore
        self.supportsAdvancedGraphics = supportsAdvancedGraphics
    }

    // MARK: - Factory

    /// Capacités typiques dérivées du tier.
    public static func from(tier: DeviceTierSnapshot) -> DeviceCapabilities {
        switch tier {
        case .premium:
            return DeviceCapabilities(maxMemoryMB: 6144, cpuScore: 90, supportsAdvancedGraphics: true)
        case .midRange:
            return DeviceCapabilities(maxMemoryMB: 3072, cpuScore: 60, supportsAdvancedGraphics: true)
        case .lowEnd:
            return DeviceCapabilities(maxMemoryMB: 1024, cpuScore: 30, supportsAdvancedGraphics: false)
        }
    }
}
