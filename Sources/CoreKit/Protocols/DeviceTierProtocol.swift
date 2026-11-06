//
//  DeviceTierProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

// MARK: - DeviceTierSnapshot

/// Tier hardware du device — ordre croissant : lowEnd < midRange < premium.
///
/// Calculé une seule fois au bootstrap par `DeviceTier` (DeviceKit)
/// à partir du `DeviceInfoSnapshot`.
///
/// Utilisé par :
/// - `UIConfiguration` (App) : qualité images/animations
/// - `DeviceCapabilities.from(tier:)` : capacités hardware dérivées
/// - `NetworkKit` (futur) : calibrage retry, timeout, concurrence
public enum DeviceTierSnapshot: String, Sendable, Comparable, CustomStringConvertible {
    case lowEnd   = "low-end"
    case midRange = "mid-range"
    case premium  = "premium"

    public var description: String { rawValue }

    public static func < (lhs: DeviceTierSnapshot, rhs: DeviceTierSnapshot) -> Bool {
        let order: [DeviceTierSnapshot] = [.lowEnd, .midRange, .premium]
        guard let l = order.firstIndex(of: lhs),
              let r = order.firstIndex(of: rhs) else { return false }
        return l < r
    }
}

// MARK: - DeviceTierProtocol

/// Contrat de résolution du tier device.
/// L'implémentation concrète (`DeviceTier` actor) vit dans DeviceKit.
public protocol DeviceTierProtocol: Sendable {
    func getDeviceTier() async -> DeviceTierSnapshot
}
