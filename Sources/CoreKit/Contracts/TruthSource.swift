import Foundation

/// Represents the authoritative source of truth for data
/// Used to track where data originates and ensure consistency
public enum TruthSource: String, Codable, Sendable {
    /// Data originates from the backend server
    case backend = "BACKEND"
    
    /// Data originates from local device
    case local = "LOCAL"
    
    /// Data originates from peer device (P2P)
    case peer = "PEER"
    
    /// Data originates from cache
    case cache = "CACHE"
    
    /// Data originates from offline queue
    case offlineQueue = "OFFLINE_QUEUE"
    
    /// Data source is unknown or mixed
    case unknown = "UNKNOWN"
    
    /// Priority order for conflict resolution (higher = more authoritative)
    public var priority: Int {
        switch self {
        case .backend: return 100
        case .peer: return 50
        case .local: return 30
        case .cache: return 20
        case .offlineQueue: return 10
        case .unknown: return 0
        }
    }
    
    /// Whether this source is considered authoritative
    public var isAuthoritative: Bool {
        self == .backend
    }
    
    /// Whether this source requires sync with backend
    public var requiresSync: Bool {
        switch self {
        case .local, .offlineQueue:
            return true
        default:
            return false
        }
    }
}

/// Protocol for entities that track their source of truth
public protocol TruthSourceTracking {
    var truthSource: TruthSource { get }
    var lastSyncedAt: Date? { get }
    var needsSync: Bool { get }
}

/// Extension to provide default implementation
public extension TruthSourceTracking {
    var needsSync: Bool {
        truthSource.requiresSync || lastSyncedAt == nil
    }
}
