import Foundation

/// Unique identifier for correlating requests across distributed systems
/// Enables tracing a single operation through multiple services
public struct CorrelationId: Codable, Hashable, Sendable {
    public let value: String
    
    /// Creates a new correlation ID with a UUID
    public init() {
        self.value = UUID().uuidString
    }
    
    /// Creates a correlation ID from an existing string
    public init(value: String) {
        self.value = value
    }
    
    /// Creates a correlation ID from a UUID
    public init(uuid: UUID) {
        self.value = uuid.uuidString
    }
    
    /// HTTP header name for correlation ID
    public static let headerName = "X-Correlation-ID"
    
    /// Creates a child correlation ID for nested operations
    public func child(suffix: String) -> CorrelationId {
        CorrelationId(value: "\(value)-\(suffix)")
    }
}

extension CorrelationId: CustomStringConvertible {
    public var description: String {
        value
    }
}

extension CorrelationId: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.value = value
    }
}

/// Protocol for operations that can be correlated
public protocol Correlatable {
    var correlationId: CorrelationId { get }
}

/// Thread-safe correlation context for tracking current operation
@globalActor
public actor CorrelationContext {
    public static let shared = CorrelationContext()
    
    private var currentId: CorrelationId?
    
    private init() {}
    
    /// Set the current correlation ID for this context
    public func setCurrent(_ id: CorrelationId) {
        currentId = id
    }
    
    /// Get the current correlation ID, or create a new one
    public func getCurrent() -> CorrelationId {
        if let current = currentId {
            return current
        }
        let newId = CorrelationId()
        currentId = newId
        return newId
    }
    
    /// Clear the current correlation ID
    public func clear() {
        currentId = nil
    }
}
