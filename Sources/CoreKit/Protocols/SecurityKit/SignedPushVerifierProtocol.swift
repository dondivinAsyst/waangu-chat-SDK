//
//  SignedPushVerifierProtocol.swift
//  CoreKit
//
//  Protocol abstraction for SignedPushVerifier

import Foundation

/// Verified push notification
public struct VerifiedPush: Sendable {
    public let payload: [String: Any]
    public let timestamp: Date
    public let verified: Bool
    
    public init(payload: [String: Any], timestamp: Date, verified: Bool) {
        self.payload = payload
        self.timestamp = timestamp
        self.verified = verified
    }
    
    /// Extract typed value from payload
    public func value<T>(forKey key: String) -> T? {
        payload[key] as? T
    }
}

/// Signed push notification
public struct SignedPush: Sendable {
    public let payload: [String: Any]
    public let signature: String
    public let timestamp: String
    
    public init(payload: [String: Any], signature: String, timestamp: String) {
        self.payload = payload
        self.signature = signature
        self.timestamp = timestamp
    }
}

/// Push verification errors
public enum PushVerificationError: Error, LocalizedError {
    case signingKeyNotConfigured
    case invalidSigningKey
    case missingSignature
    case missingTimestamp
    case invalidTimestamp
    case timestampExpired(age: TimeInterval)
    case signatureMismatch
    case invalidPayload
    
    public var errorDescription: String? {
        switch self {
        case .signingKeyNotConfigured:
            return "Push signing key not configured"
        case .invalidSigningKey:
            return "Invalid signing key format"
        case .missingSignature:
            return "Push notification missing signature"
        case .missingTimestamp:
            return "Push notification missing timestamp"
        case .invalidTimestamp:
            return "Invalid timestamp format"
        case .timestampExpired(let age):
            return "Push notification expired (age: \(Int(age))s)"
        case .signatureMismatch:
            return "Push notification signature verification failed"
        case .invalidPayload:
            return "Invalid push notification payload"
        }
    }
}

public protocol SignedPushVerifierProtocol: Sendable {
    /// Set the signing key for verification
    func setSigningKey(_ key: Data) async
    
    /// Set signing key from base64 string
    func setSigningKey(base64: String) async throws
    
    /// Verify push notification payload
    func verify(
        payload: [String: Any],
        signature: String,
        timestamp: String
    ) async throws -> VerifiedPush
    
    /// Verify push notification from UserInfo dictionary
    func verify(userInfo: [AnyHashable: Any]) async throws -> VerifiedPush
    
    /// Sign a push payload (for testing/development)
    func sign(payload: [String: Any]) async throws -> SignedPush
}