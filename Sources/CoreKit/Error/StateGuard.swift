import Foundation

/// Prevents unknown states from becoming success
/// Enforces explicit state handling with compile-time safety
public enum StateGuard {
    
    /// Result type that prevents unknown states from being treated as success
    public enum GuardedResult<Success, Failure: Error> {
        case success(Success)
        case failure(Failure)
        case unknown(reason: String)
        
        /// Get value, throwing if not success
        /// Unknown states throw UnknownStateError
        public func get() throws -> Success {
            switch self {
            case .success(let value):
                return value
            case .failure(let error):
                throw error
            case .unknown(let reason):
                throw UnknownStateError.cannotBecomeSuccess(reason: reason)
            }
        }
        
        /// Check if result is success
        public var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
        
        /// Check if result is failure
        public var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }
        
        /// Check if result is unknown
        public var isUnknown: Bool {
            if case .unknown = self { return true }
            return false
        }
        
        /// Map success value
        public func map<NewSuccess>(_ transform: (Success) -> NewSuccess) -> GuardedResult<NewSuccess, Failure> {
            switch self {
            case .success(let value):
                return .success(transform(value))
            case .failure(let error):
                return .failure(error)
            case .unknown(let reason):
                return .unknown(reason: reason)
            }
        }
        
        /// FlatMap for chaining operations
        public func flatMap<NewSuccess>(_ transform: (Success) -> GuardedResult<NewSuccess, Failure>) -> GuardedResult<NewSuccess, Failure> {
            switch self {
            case .success(let value):
                return transform(value)
            case .failure(let error):
                return .failure(error)
            case .unknown(let reason):
                return .unknown(reason: reason)
            }
        }
    }
    
    /// Validate HTTP status code, preventing unknown codes from becoming success
    public static func validateHTTPStatus(_ statusCode: Int) -> GuardedResult<Int, HTTPStatusError> {
        switch statusCode {
        // Explicit success codes
        case 200, 201, 202, 204, 304:
            return .success(statusCode)
            
        // Explicit client errors
        case 400:
            return .failure(.badRequest)
        case 401:
            return .failure(.unauthorized)
        case 403:
            return .failure(.forbidden)
        case 404:
            return .failure(.notFound)
        case 409:
            return .failure(.conflict)
        case 429:
            return .failure(.rateLimited)
            
        // Explicit server errors
        case 500:
            return .failure(.internalServerError)
        case 502:
            return .failure(.badGateway)
        case 503:
            return .failure(.serviceUnavailable)
        case 504:
            return .failure(.gatewayTimeout)
            
        // Known but unhandled success codes
        case 100...199:
            return .unknown(reason: "Informational status \(statusCode) not explicitly handled")
        case 203, 205...299:
            return .unknown(reason: "Success status \(statusCode) not explicitly handled")
            
        // Known but unhandled client errors
        case 402, 405...428, 430...499:
            return .unknown(reason: "Client error \(statusCode) not explicitly handled")
            
        // Known but unhandled server errors
        case 501, 505...599:
            return .unknown(reason: "Server error \(statusCode) not explicitly handled")
            
        // Completely unknown codes
        default:
            return .unknown(reason: "Unknown HTTP status code: \(statusCode)")
        }
    }
    
    /// Validate operation state, preventing unknown states from becoming success
    public static func validateOperationState(_ state: String) -> GuardedResult<OperationState, StateError> {
        switch state.uppercased() {
        case "SUCCESS", "COMPLETED", "DONE":
            return .success(.completed)
        case "PENDING", "IN_PROGRESS", "PROCESSING":
            return .success(.pending)
        case "FAILED", "ERROR":
            return .failure(.operationFailed)
        case "CANCELLED", "ABORTED":
            return .failure(.operationCancelled)
        case "TIMEOUT":
            return .failure(.operationTimeout)
        default:
            return .unknown(reason: "Unknown operation state: \(state)")
        }
    }
    
    /// Validate message delivery status
    public static func validateDeliveryStatus(_ status: String) -> GuardedResult<DeliveryStatus, StateError> {
        switch status.uppercased() {
        case "DELIVERED", "SENT":
            return .success(.delivered)
        case "PENDING", "QUEUED":
            return .success(.pending)
        case "FAILED":
            return .failure(.deliveryFailed)
        case "REJECTED":
            return .failure(.deliveryRejected)
        default:
            return .unknown(reason: "Unknown delivery status: \(status)")
        }
    }
}

// MARK: - Errors

public enum UnknownStateError: Error, LocalizedError {
    case cannotBecomeSuccess(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .cannotBecomeSuccess(let reason):
            return "Unknown state cannot become success: \(reason)"
        }
    }
}

public enum HTTPStatusError: Error, LocalizedError {
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case rateLimited
    case internalServerError
    case badGateway
    case serviceUnavailable
    case gatewayTimeout
    
    public var errorDescription: String? {
        switch self {
        case .badRequest: return "Bad request"
        case .unauthorized: return "Unauthorized"
        case .forbidden: return "Forbidden"
        case .notFound: return "Not found"
        case .conflict: return "Conflict"
        case .rateLimited: return "Rate limited"
        case .internalServerError: return "Internal server error"
        case .badGateway: return "Bad gateway"
        case .serviceUnavailable: return "Service unavailable"
        case .gatewayTimeout: return "Gateway timeout"
        }
    }
}

public enum StateError: Error, LocalizedError {
    case operationFailed
    case operationCancelled
    case operationTimeout
    case deliveryFailed
    case deliveryRejected
    
    public var errorDescription: String? {
        switch self {
        case .operationFailed: return "Operation failed"
        case .operationCancelled: return "Operation cancelled"
        case .operationTimeout: return "Operation timeout"
        case .deliveryFailed: return "Delivery failed"
        case .deliveryRejected: return "Delivery rejected"
        }
    }
}

// MARK: - State Types

public enum OperationState: String, Sendable {
    case completed = "COMPLETED"
    case pending = "PENDING"
}

public enum DeliveryStatus: String, Sendable {
    case delivered = "DELIVERED"
    case pending = "PENDING"
}

// MARK: - Usage Examples

/*
 Example 1: HTTP Status Validation
 
 let result = StateGuard.validateHTTPStatus(statusCode)
 
 switch result {
 case .success(let code):
     print("Success: \(code)")
 case .failure(let error):
     print("Known error: \(error)")
 case .unknown(let reason):
     // Unknown states CANNOT become success
     // Must be explicitly handled or logged
     await AuditBreadcrumb.shared.record(
         action: .errorOccurred,
         category: .system,
         metadata: ["unknown_state": reason],
         severity: .critical
     )
     throw UnknownStateError.cannotBecomeSuccess(reason: reason)
 }
 
 Example 2: Operation State Validation
 
 let result = StateGuard.validateOperationState(serverState)
 
 do {
     let state = try result.get() // Throws if unknown
     handleState(state)
 } catch UnknownStateError.cannotBecomeSuccess(let reason) {
     // Log and handle unknown state
     await logUnknownState(reason)
 }
 
 Example 3: Chaining with map/flatMap
 
 let result = StateGuard.validateHTTPStatus(200)
     .map { code in
         // Transform success value
         return "HTTP \(code)"
     }
     .flatMap { message in
         // Chain another guarded operation
         return .success(message.uppercased())
     }
 */
