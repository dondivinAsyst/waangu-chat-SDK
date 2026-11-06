import Foundation

/// Identifies which backend service owns a particular piece of data
/// Enables proper routing and ownership tracking in microservices
public enum BackendOwner: String, Codable, Sendable {
    /// Chat service owns this data
    case chatService = "CHAT_SERVICE"
    
    /// Message service owns this data
    case messageService = "MESSAGE_SERVICE"
    
    /// Contact service owns this data
    case contactService = "CONTACT_SERVICE"
    
    /// Media service owns this data
    case mediaService = "MEDIA_SERVICE"
    
    /// E2EE service owns this data
    case e2eeService = "E2EE_SERVICE"
    
    /// Status service owns this data
    case statusService = "STATUS_SERVICE"
    
    /// Group service owns this data
    case groupService = "GROUP_SERVICE"
    
    /// Auth service owns this data
    case authService = "AUTH_SERVICE"
    
    /// Notification service owns this data
    case notificationService = "NOTIFICATION_SERVICE"
    
    /// Analytics service owns this data
    case analyticsService = "ANALYTICS_SERVICE"
    
    /// Unknown or multiple owners
    case unknown = "UNKNOWN"
    
    /// Base URL for this service (configure based on environment)
    public var baseURL: String {
        // TODO: Load from configuration
        switch self {
        case .chatService:
            return "https://api.waangu.com/chat"
        case .messageService:
            return "https://api.waangu.com/messages"
        case .contactService:
            return "https://api.waangu.com/contacts"
        case .mediaService:
            return "https://api.waangu.com/media"
        case .e2eeService:
            return "https://api.waangu.com/e2ee"
        case .statusService:
            return "https://api.waangu.com/status"
        case .groupService:
            return "https://api.waangu.com/groups"
        case .authService:
            return "https://api.waangu.com/auth"
        case .notificationService:
            return "https://api.waangu.com/notifications"
        case .analyticsService:
            return "https://api.waangu.com/analytics"
        case .unknown:
            return ""
        }
    }
    
    /// Whether this service requires authentication
    public var requiresAuth: Bool {
        self != .unknown
    }
    
    /// Service timeout in seconds
    public var timeout: TimeInterval {
        switch self {
        case .mediaService:
            return 60.0 // Longer for uploads
        case .analyticsService:
            return 5.0 // Shorter for non-critical
        default:
            return 30.0
        }
    }
}

/// Protocol for data that has a backend owner
public protocol BackendOwned {
    var backendOwner: BackendOwner { get }
}

/// Service registry for managing backend services
public final class BackendServiceRegistry {
    public static let shared = BackendServiceRegistry()
    
    private var serviceEndpoints: [BackendOwner: String] = [:]
    private var serviceHealth: [BackendOwner: ServiceHealth] = [:]
    
    private init() {
        // Initialize with default endpoints
        BackendOwner.allCases.forEach { owner in
            serviceEndpoints[owner] = owner.baseURL
            serviceHealth[owner] = .unknown
        }
    }
    
    /// Update endpoint for a service
    public func updateEndpoint(for owner: BackendOwner, endpoint: String) {
        serviceEndpoints[owner] = endpoint
    }
    
    /// Get endpoint for a service
    public func endpoint(for owner: BackendOwner) -> String? {
        serviceEndpoints[owner]
    }
    
    /// Update health status for a service
    public func updateHealth(for owner: BackendOwner, health: ServiceHealth) {
        serviceHealth[owner] = health
    }
    
    /// Get health status for a service
    public func health(for owner: BackendOwner) -> ServiceHealth {
        serviceHealth[owner] ?? .unknown
    }
    
    /// Check if service is healthy
    public func isHealthy(_ owner: BackendOwner) -> Bool {
        health(for: owner) == .healthy
    }
}

/// Service health status
public enum ServiceHealth: String, Codable {
    case healthy = "HEALTHY"
    case degraded = "DEGRADED"
    case unhealthy = "UNHEALTHY"
    case unknown = "UNKNOWN"
}

extension BackendOwner: CaseIterable {}
