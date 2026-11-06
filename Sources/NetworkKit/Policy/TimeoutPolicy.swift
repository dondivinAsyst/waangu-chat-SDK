// MARK: - NetworkKit/Policy/TimeoutPolicy.swift

import Foundation

/// Politique de timeout par endpoint.
/// Le timeout final est calculé par APIClient :
/// `min(max(baseTimeout × timeoutMultiplier, minTimeout), maxTimeout)`
public enum EndpointTimeoutPolicy: Sendable {
    case fast               // 8s  — health checks, lookups
    case standard           // 20s — endpoints REST classiques
    case long               // 60s — exports, génération de rapports
    case custom(TimeInterval)

    public var baseTimeout: TimeInterval {
        switch self {
        case .fast:              return 8
        case .standard:          return 20
        case .long:              return 60
        case .custom(let t):     return t
        }
    }
}
