import Foundation

/// Validates and enforces TraceContext on all critical operations
/// Ensures distributed tracing across all service calls
public actor TraceContextValidator {
    
    public static let shared = TraceContextValidator()
    
    private var activeTraces: [String: TraceContext] = [:]
    
    private init() {}
    
    public struct TraceContext: Sendable {
        public let traceId: String
        public let spanId: String
        public let parentSpanId: String?
        public let timestamp: Date
        public let operationName: String
        
        public init(
            traceId: String = UUID().uuidString,
            spanId: String = UUID().uuidString,
            parentSpanId: String? = nil,
            operationName: String
        ) {
            self.traceId = traceId
            self.spanId = spanId
            self.parentSpanId = parentSpanId
            self.timestamp = Date()
            self.operationName = operationName
        }
    }
    
    /// Creates a new trace context for an operation
    public func createTraceContext(operationName: String, parentSpanId: String? = nil) -> TraceContext {
        let context = TraceContext(
            parentSpanId: parentSpanId,
            operationName: operationName
        )
        activeTraces[context.traceId] = context
        return context
    }
    
    /// Validates that a trace context exists and is valid
    public func validateTraceContext(_ traceId: String) throws {
        guard activeTraces[traceId] != nil else {
            throw TraceContextError.missingTraceContext(traceId: traceId)
        }
    }
    
    /// Gets trace context for a trace ID
    public func getTraceContext(_ traceId: String) -> TraceContext? {
        activeTraces[traceId]
    }
    
    /// Completes a trace
    public func completeTrace(_ traceId: String) {
        activeTraces.removeValue(forKey: traceId)
    }
    
    /// Validates all critical operations have trace context
    public func validateCriticalOperationHasTrace(_ operationName: String) throws {
        let hasCriticalTrace = activeTraces.values.contains { context in
            context.operationName == operationName
        }
        
        guard hasCriticalTrace else {
            throw TraceContextError.criticalOperationMissingTrace(operation: operationName)
        }
    }
    
    /// Gets all active traces
    public func getActiveTraces() -> [TraceContext] {
        Array(activeTraces.values)
    }
}

public enum TraceContextError: Error {
    case missingTraceContext(traceId: String)
    case criticalOperationMissingTrace(operation: String)
}
