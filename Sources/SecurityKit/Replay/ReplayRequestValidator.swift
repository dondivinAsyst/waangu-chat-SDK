//
//  ReplayRequestValidator.swift
//  SecurityKit
//
//  RULE: ReplayRequest validé
//  Validates replay requests to prevent replay attacks

import Foundation
import WaanguCoreKit

/// Validates replay requests
/// RULE: Prevents replay attacks by tracking request nonces
public actor ReplayRequestValidator {
    
    public static let shared = ReplayRequestValidator()
    
    private var processedRequests: Set<String> = []
    private var requestTimestamps: [String: Date] = [:]
    private let nonceExpirationTime: TimeInterval = 300 // 5 minutes
    private let maxProcessedRequests = 10000
    
    private init() {}
    
    // MARK: - Request Validation
    
    /// Validates a replay request
    /// RULE: Request must have unique nonce and valid timestamp
    public func validateRequest(_ request: ReplayRequest) async throws {
        
        // Check nonce uniqueness
        guard !processedRequests.contains(request.nonce) else {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: request.userId,
                metadata: [
                    "violation": "replay_attack_detected",
                    "nonce": request.nonce,
                    "requestId": request.requestId
                ]
            )
            throw ReplayRequestError.duplicateNonce(nonce: request.nonce)
        }
        
        // Check timestamp freshness
        let now = Date()
        let age = now.timeIntervalSince(request.timestamp)
        
        guard age >= 0 && age < nonceExpirationTime else {
            throw ReplayRequestError.expiredTimestamp(timestamp: request.timestamp)
        }
        
        // Verify signature
        guard try await verifySignature(request) else {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: request.userId,
                metadata: [
                    "violation": "invalid_replay_request_signature",
                    "requestId": request.requestId
                ]
            )
            throw ReplayRequestError.invalidSignature
        }
        
        // Mark as processed
        processedRequests.insert(request.nonce)
        requestTimestamps[request.nonce] = request.timestamp
        
        // Limit set size
        if processedRequests.count > maxProcessedRequests {
            cleanupOldRequests()
        }
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "operation": "replay_request_validated",
                "requestId": request.requestId,
                "userId": request.userId
            ]
        )
    }
    
    // MARK: - Signature Verification
    
    private func verifySignature(_ request: ReplayRequest) async throws -> Bool {
        // In production: Verify with backend public key
        // For now: Basic validation
        guard !request.signature.isEmpty && request.signature.count >= 64 else {
            return false
        }
        
        guard Data(base64Encoded: request.signature) != nil else {
            return false
        }
        
        return true
    }
    
    // MARK: - Cleanup
    
    private func cleanupOldRequests() {
        let now = Date()
        let expiredNonces = requestTimestamps.filter { now.timeIntervalSince($0.value) > nonceExpirationTime }.map { $0.key }
        
        for nonce in expiredNonces {
            processedRequests.remove(nonce)
            requestTimestamps.removeValue(forKey: nonce)
        }
    }
    
    public func cleanupExpired() {
        cleanupOldRequests()
    }
    
    public func getStatistics() -> ReplayStatistics {
        return ReplayStatistics(
            processedRequests: processedRequests.count,
            oldestTimestamp: requestTimestamps.values.min()
        )
    }
    
    public func reset() {
        processedRequests.removeAll()
        requestTimestamps.removeAll()
    }
}

// MARK: - Types

public struct ReplayRequest: Sendable {
    public let requestId: String
    public let userId: String
    public let nonce: String
    public let timestamp: Date
    public let signature: String
    public let payload: [String: String]
    
    public init(
        requestId: String,
        userId: String,
        nonce: String,
        timestamp: Date,
        signature: String,
        payload: [String: String]
    ) {
        self.requestId = requestId
        self.userId = userId
        self.nonce = nonce
        self.timestamp = timestamp
        self.signature = signature
        self.payload = payload
    }
}

public enum ReplayRequestError: Error, LocalizedError {
    case duplicateNonce(nonce: String)
    case expiredTimestamp(timestamp: Date)
    case invalidSignature
    case invalidFormat
    
    public var errorDescription: String? {
        switch self {
        case .duplicateNonce(let nonce):
            return "Replay attack detected: duplicate nonce \(nonce)"
        case .expiredTimestamp(let timestamp):
            return "Request timestamp expired: \(timestamp)"
        case .invalidSignature:
            return "Invalid request signature"
        case .invalidFormat:
            return "Invalid request format"
        }
    }
}

public struct ReplayStatistics: Sendable {
    public let processedRequests: Int
    public let oldestTimestamp: Date?
    
    public init(processedRequests: Int, oldestTimestamp: Date?) {
        self.processedRequests = processedRequests
        self.oldestTimestamp = oldestTimestamp
    }
}
