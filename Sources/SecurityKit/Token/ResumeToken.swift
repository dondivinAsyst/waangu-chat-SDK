//
//  ResumeToken.swift
//  SecurityKit
//
//  RULE: ResumeToken signé
//  Signed resume tokens for secure session continuation

import Foundation
import CryptoKit
import WaanguCoreKit

/// Signed resume token for secure session continuation
/// RULE: Resume tokens must be signed by backend
public actor ResumeTokenManager {
    
    public static let shared = ResumeTokenManager()
    
    private var activeTokens: [String: ResumeToken] = [:]
    private let signingKey: SymmetricKey
    
    private init() {
        self.signingKey = SymmetricKey(size: .bits256)
    }
    
    // MARK: - Token Validation
    
    /// Validates a resume token
    /// RULE: Token must have valid signature and not be expired
    public func validateToken(_ encoded: String) async throws -> ResumeToken {
        
        // Decode token
        let token = try decodeToken(encoded)
        
        // Verify signature
        guard try verifySignature(token) else {
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: token.userId,
                metadata: [
                    "violation": "invalid_resume_token_signature",
                    "tokenId": token.tokenId
                ]
            )
            throw ResumeTokenError.invalidSignature
        }
        
        // Check expiration
        guard token.expiresAt > Date() else {
            throw ResumeTokenError.expired(expiresAt: token.expiresAt)
        }
        
        // Check if token is revoked
        if token.isRevoked {
            throw ResumeTokenError.revoked
        }
        
        // Store active token
        activeTokens[token.tokenId] = token
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "operation": "resume_token_validated",
                "tokenId": token.tokenId,
                "userId": token.userId
            ]
        )
        
        return token
    }
    
    /// Creates a new resume token (backend only)
    public func createToken(
        userId: String,
        sessionId: String,
        lastSequence: Int64,
        expiresAt: Date
    ) async throws -> String {
        
        let token = ResumeToken(
            tokenId: UUID().uuidString,
            userId: userId,
            sessionId: sessionId,
            lastSequence: lastSequence,
            issuedAt: Date(),
            expiresAt: expiresAt,
            signature: "",
            isRevoked: false
        )
        
        // Generate signature
        let signature = try generateSignature(token)
        let signedToken = ResumeToken(
            tokenId: token.tokenId,
            userId: token.userId,
            sessionId: token.sessionId,
            lastSequence: token.lastSequence,
            issuedAt: token.issuedAt,
            expiresAt: token.expiresAt,
            signature: signature,
            isRevoked: false
        )
        
        // Store
        activeTokens[signedToken.tokenId] = signedToken
        
        // Encode
        return try encodeToken(signedToken)
    }
    
    /// Revokes a token
    public func revokeToken(tokenId: String) async {
        if var token = activeTokens[tokenId] {
            token = ResumeToken(
                tokenId: token.tokenId,
                userId: token.userId,
                sessionId: token.sessionId,
                lastSequence: token.lastSequence,
                issuedAt: token.issuedAt,
                expiresAt: token.expiresAt,
                signature: token.signature,
                isRevoked: true
            )
            activeTokens[tokenId] = token
        }
        
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: nil,
            metadata: [
                "operation": "resume_token_revoked",
                "tokenId": tokenId
            ]
        )
    }
    
    // MARK: - Signature Operations
    
    private func verifySignature(_ token: ResumeToken) throws -> Bool {
        let data = try encodeForSigning(token)
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: data, using: signingKey)
        
        guard let signatureData = Data(base64Encoded: token.signature) else {
            return false
        }
        
        return Data(expectedSignature) == signatureData
    }
    
    private func generateSignature(_ token: ResumeToken) throws -> String {
        let data = try encodeForSigning(token)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: signingKey)
        return Data(signature).base64EncodedString()
    }
    
    private func encodeForSigning(_ token: ResumeToken) throws -> Data {
        let signingData = "\(token.tokenId):\(token.userId):\(token.sessionId):\(token.lastSequence):\(token.issuedAt.timeIntervalSince1970):\(token.expiresAt.timeIntervalSince1970)"
        return Data(signingData.utf8)
    }
    
    // MARK: - Encoding/Decoding
    
    private func encodeToken(_ token: ResumeToken) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(token)
        return data.base64EncodedString()
    }
    
    private func decodeToken(_ encoded: String) throws -> ResumeToken {
        guard let data = Data(base64Encoded: encoded) else {
            throw ResumeTokenError.invalidFormat
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResumeToken.self, from: data)
    }
    
    // MARK: - Cleanup
    
    public func cleanupExpired() {
        let now = Date()
        activeTokens = activeTokens.filter { $0.value.expiresAt > now }
    }
    
    public func getActiveToken(tokenId: String) -> ResumeToken? {
        return activeTokens[tokenId]
    }
}

// MARK: - Types

public struct ResumeToken: Codable, Sendable {
    public let tokenId: String
    public let userId: String
    public let sessionId: String
    public let lastSequence: Int64
    public let issuedAt: Date
    public let expiresAt: Date
    public let signature: String
    public let isRevoked: Bool
    
    public init(
        tokenId: String,
        userId: String,
        sessionId: String,
        lastSequence: Int64,
        issuedAt: Date,
        expiresAt: Date,
        signature: String,
        isRevoked: Bool
    ) {
        self.tokenId = tokenId
        self.userId = userId
        self.sessionId = sessionId
        self.lastSequence = lastSequence
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.signature = signature
        self.isRevoked = isRevoked
    }
}

public enum ResumeTokenError: Error, LocalizedError {
    case invalidSignature
    case invalidFormat
    case expired(expiresAt: Date)
    case revoked
    
    public var errorDescription: String? {
        switch self {
        case .invalidSignature:
            return "Resume token signature is invalid"
        case .invalidFormat:
            return "Resume token format is invalid"
        case .expired(let expiresAt):
            return "Resume token expired at \(expiresAt)"
        case .revoked:
            return "Resume token has been revoked"
        }
    }
}
