import Foundation

/// Standardized reason codes for errors and state changes
/// Provides machine-readable error classification
public enum SovereignReasonCode: String, Codable, Sendable {
    // MARK: - Success Codes (1xxx)
    case success = "1000"
    case created = "1001"
    case accepted = "1002"
    case noContent = "1003"
    
    // MARK: - Client Error Codes (4xxx)
    case badRequest = "4000"
    case unauthorized = "4001"
    case forbidden = "4003"
    case notFound = "4004"
    case conflict = "4009"
    case gone = "4010"
    case unprocessableEntity = "4022"
    case tooManyRequests = "4029"
    
    // MARK: - Server Error Codes (5xxx)
    case internalServerError = "5000"
    case notImplemented = "5001"
    case badGateway = "5002"
    case serviceUnavailable = "5003"
    case gatewayTimeout = "5004"
    
    // MARK: - Network Error Codes (6xxx)
    case networkUnreachable = "6000"
    case connectionTimeout = "6001"
    case connectionLost = "6002"
    case dnsFailure = "6003"
    case sslError = "6004"
    
    // MARK: - Data Error Codes (7xxx)
    case dataCorrupted = "7000"
    case dataNotFound = "7001"
    case dataConflict = "7002"
    case dataValidationFailed = "7003"
    case dataEncryptionFailed = "7004"
    case dataDecryptionFailed = "7005"
    
    // MARK: - Business Logic Error Codes (8xxx)
    case messageNotDelivered = "8000"
    case messageExpired = "8001"
    case messageDeleted = "8002"
    case userBlocked = "8003"
    case groupFull = "8004"
    case permissionDenied = "8005"
    case quotaExceeded = "8006"
    case featureDisabled = "8007"
    
    // MARK: - Security Error Codes (9xxx)
    case authenticationFailed = "9000"
    case tokenExpired = "9001"
    case tokenInvalid = "9002"
    case signatureInvalid = "9003"
    case encryptionRequired = "9004"
    case deviceNotTrusted = "9005"
    case integrityCheckFailed = "9006"
    
    /// Human-readable description
    public var description: String {
        switch self {
        // Success
        case .success: return "Operation completed successfully"
        case .created: return "Resource created successfully"
        case .accepted: return "Request accepted for processing"
        case .noContent: return "Operation successful, no content to return"
            
        // Client errors
        case .badRequest: return "Invalid request parameters"
        case .unauthorized: return "Authentication required"
        case .forbidden: return "Access forbidden"
        case .notFound: return "Resource not found"
        case .conflict: return "Resource conflict"
        case .gone: return "Resource no longer available"
        case .unprocessableEntity: return "Request cannot be processed"
        case .tooManyRequests: return "Rate limit exceeded"
            
        // Server errors
        case .internalServerError: return "Internal server error"
        case .notImplemented: return "Feature not implemented"
        case .badGateway: return "Bad gateway"
        case .serviceUnavailable: return "Service temporarily unavailable"
        case .gatewayTimeout: return "Gateway timeout"
            
        // Network errors
        case .networkUnreachable: return "Network unreachable"
        case .connectionTimeout: return "Connection timeout"
        case .connectionLost: return "Connection lost"
        case .dnsFailure: return "DNS resolution failed"
        case .sslError: return "SSL/TLS error"
            
        // Data errors
        case .dataCorrupted: return "Data corrupted"
        case .dataNotFound: return "Data not found"
        case .dataConflict: return "Data conflict detected"
        case .dataValidationFailed: return "Data validation failed"
        case .dataEncryptionFailed: return "Data encryption failed"
        case .dataDecryptionFailed: return "Data decryption failed"
            
        // Business logic errors
        case .messageNotDelivered: return "Message not delivered"
        case .messageExpired: return "Message expired"
        case .messageDeleted: return "Message deleted"
        case .userBlocked: return "User blocked"
        case .groupFull: return "Group is full"
        case .permissionDenied: return "Permission denied"
        case .quotaExceeded: return "Quota exceeded"
        case .featureDisabled: return "Feature disabled"
            
        // Security errors
        case .authenticationFailed: return "Authentication failed"
        case .tokenExpired: return "Token expired"
        case .tokenInvalid: return "Token invalid"
        case .signatureInvalid: return "Signature invalid"
        case .encryptionRequired: return "Encryption required"
        case .deviceNotTrusted: return "Device not trusted"
        case .integrityCheckFailed: return "Integrity check failed"
        }
    }
    
    /// Category of the error
    public var category: ErrorCategory {
        let code = Int(rawValue) ?? 0
        switch code {
        case 1000..<2000: return .success
        case 4000..<5000: return .clientError
        case 5000..<6000: return .serverError
        case 6000..<7000: return .networkError
        case 7000..<8000: return .dataError
        case 8000..<9000: return .businessLogicError
        case 9000..<10000: return .securityError
        default: return .unknown
        }
    }
    
    /// Whether this is a retryable error
    public var isRetryable: Bool {
        switch self {
        case .networkUnreachable, .connectionTimeout, .connectionLost,
             .serviceUnavailable, .gatewayTimeout, .tooManyRequests:
            return true
        default:
            return false
        }
    }
    
    /// Whether this requires user action
    public var requiresUserAction: Bool {
        switch self {
        case .unauthorized, .forbidden, .tokenExpired,
             .authenticationFailed, .permissionDenied:
            return true
        default:
            return false
        }
    }
}

/// Error category classification
public enum ErrorCategory: String, Codable {
    case success
    case clientError
    case serverError
    case networkError
    case dataError
    case businessLogicError
    case securityError
    case unknown
}

/// Protocol for errors with reason codes
public protocol ReasonCoded {
    var reasonCode: SovereignReasonCode { get }
}

/// Structured error with reason code
public struct SovereignError: Error, Codable, ReasonCoded {
    public let reasonCode: SovereignReasonCode
    public let message: String
    public let metadata: [String: String]?
    public let timestamp: Date
    
    public init(
        reasonCode: SovereignReasonCode,
        message: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.reasonCode = reasonCode
        self.message = message ?? reasonCode.description
        self.metadata = metadata
        self.timestamp = Date()
    }
}

extension SovereignError: LocalizedError {
    public var errorDescription: String? {
        message
    }
}
