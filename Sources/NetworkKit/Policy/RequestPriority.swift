// MARK: - NetworkKit/Policy/RequestPriority.swift
//
// Priorité d'une requête HTTP.
// Défini dans NetworkKit/Policy — concept réseau utilisé par EndpointPolicyProviding.

import Foundation

public enum RequestPriority: Int, Comparable, Sendable {
    case critical   = 0  // Paiements, auth — ne jamais throttler
    case high       = 1  // Actions utilisateur directes
    case medium     = 2  // Chargement de contenu visible
    case low        = 3  // Prefetch, suggestions
    case background = 4  // Analytics, sync silencieuse

    public static func < (lhs: RequestPriority, rhs: RequestPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// QoS système associée — utilisée pour les URLSessionTasks.
    public var qos: QualityOfService {
        switch self {
        case .critical:   return .userInteractive
        case .high:       return .userInitiated
        case .medium:     return .default
        case .low:        return .utility
        case .background: return .background
        }
    }

    /// TaskPriority Swift Concurrency — utilisée pour les Tasks async.
    public var taskPriority: TaskPriority {
        switch self {
        case .critical, .high: return .high
        case .medium:          return .medium
        case .low:             return .low
        case .background:      return .background
        }
    }
}
