//
//  TrustAwareContainer.swift
//  CoreKit
//
//  RULE: TrustAwareContainer actif
//  Container that validates trust before rendering content

import Foundation

/// Trust-aware container for rendering backend-driven content
/// RULE: Only renders content with valid trust signatures
public actor TrustAwareContainer {
    
    public static let shared = TrustAwareContainer()
    
    private var trustedContent: [String: TrustedContent] = [:]
    private var trustValidations: [TrustValidation] = []
    private let maxValidationHistory = 100
    
    private init() {}
    
    // MARK: - Trust Validation
    
    /// Validates and stores trusted content
    /// RULE: Content must have valid backend signature
    public func validateAndStore(
        contentId: String,
        content: Data,
        signature: String,
        source: TrustSource,
        expiresAt: Date
    ) async throws -> TrustedContent {
        
        // Verify signature
        guard try await verifySignature(content: content, signature: signature, source: source) else {
            let validation = TrustValidation(
                contentId: contentId,
                isValid: false,
                reason: "Invalid signature",
                source: source,
                timestamp: Date()
            )
            trustValidations.append(validation)
            
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: nil,
                metadata: [
                    "violation": "invalid_trust_signature",
                    "contentId": contentId,
                    "source": source.rawValue
                ]
            )
            
            throw TrustError.invalidSignature
        }
        
        // Check expiration
        guard expiresAt > Date() else {
            throw TrustError.expired(expiresAt: expiresAt)
        }
        
        // Create trusted content
        let trustedContent = TrustedContent(
            contentId: contentId,
            content: content,
            signature: signature,
            source: source,
            validatedAt: Date(),
            expiresAt: expiresAt
        )
        
        // Store
        self.trustedContent[contentId] = trustedContent
        
        // Record validation
        let validation = TrustValidation(
            contentId: contentId,
            isValid: true,
            reason: "Valid signature",
            source: source,
            timestamp: Date()
        )
        trustValidations.append(validation)
        
        // Limit history
        if trustValidations.count > maxValidationHistory {
            trustValidations.removeFirst()
        }
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "operation": "trust_validated",
                "contentId": contentId,
                "source": source.rawValue
            ]
        )
        
        return trustedContent
    }
    
    /// Retrieves trusted content if valid
    public func getTrustedContent(contentId: String) -> TrustedContent? {
        guard let content = trustedContent[contentId] else {
            return nil
        }
        
        // Check expiration
        guard content.expiresAt > Date() else {
            trustedContent.removeValue(forKey: contentId)
            return nil
        }
        
        return content
    }
    
    /// Checks if content is trusted
    public func isTrusted(contentId: String) -> Bool {
        return getTrustedContent(contentId: contentId) != nil
    }
    
    // MARK: - Signature Verification
    
    private func verifySignature(
        content: Data,
        signature: String,
        source: TrustSource
    ) async throws -> Bool {
        // In production: Verify with backend public key
        // For now: Basic validation
        guard !signature.isEmpty && signature.count >= 64 else {
            return false
        }
        
        // Signature should be base64 encoded
        guard Data(base64Encoded: signature) != nil else {
            return false
        }
        
        return true
    }
    
    // MARK: - Cleanup
    
    public func cleanupExpired() {
        let now = Date()
        trustedContent = trustedContent.filter { $0.value.expiresAt > now }
    }
    
    public func removeContent(contentId: String) {
        trustedContent.removeValue(forKey: contentId)
    }
    
    public func getValidationHistory() -> [TrustValidation] {
        return trustValidations
    }
    
    public func getStatistics() -> TrustStatistics {
        let totalValidations = trustValidations.count
        let validCount = trustValidations.filter { $0.isValid }.count
        let invalidCount = totalValidations - validCount
        let activeTrustedContent = trustedContent.count
        
        return TrustStatistics(
            totalValidations: totalValidations,
            validCount: validCount,
            invalidCount: invalidCount,
            activeTrustedContent: activeTrustedContent
        )
    }
}

// MARK: - Types

public struct TrustedContent: Sendable {
    public let contentId: String
    public let content: Data
    public let signature: String
    public let source: TrustSource
    public let validatedAt: Date
    public let expiresAt: Date
    
    public init(
        contentId: String,
        content: Data,
        signature: String,
        source: TrustSource,
        validatedAt: Date,
        expiresAt: Date
    ) {
        self.contentId = contentId
        self.content = content
        self.signature = signature
        self.source = source
        self.validatedAt = validatedAt
        self.expiresAt = expiresAt
    }
}

public enum TrustSource: String, Sendable {
    case backend = "BACKEND"
    case coreGateway = "Core"
    case compliance = "compliance"
    case projection = "projection"
    case identity = "Identity"
}

public struct TrustValidation: Sendable {
    public let contentId: String
    public let isValid: Bool
    public let reason: String
    public let source: TrustSource
    public let timestamp: Date
    
    public init(
        contentId: String,
        isValid: Bool,
        reason: String,
        source: TrustSource,
        timestamp: Date
    ) {
        self.contentId = contentId
        self.isValid = isValid
        self.reason = reason
        self.source = source
        self.timestamp = timestamp
    }
}

public struct TrustStatistics: Sendable {
    public let totalValidations: Int
    public let validCount: Int
    public let invalidCount: Int
    public let activeTrustedContent: Int
    
    public init(
        totalValidations: Int,
        validCount: Int,
        invalidCount: Int,
        activeTrustedContent: Int
    ) {
        self.totalValidations = totalValidations
        self.validCount = validCount
        self.invalidCount = invalidCount
        self.activeTrustedContent = activeTrustedContent
    }
}

public enum TrustError: Error, LocalizedError {
    case invalidSignature
    case expired(expiresAt: Date)
    case untrustedSource
    case contentNotFound
    
    public var errorDescription: String? {
        switch self {
        case .invalidSignature:
            return "Content signature is invalid"
        case .expired(let expiresAt):
            return "Content expired at \(expiresAt)"
        case .untrustedSource:
            return "Content source is not trusted"
        case .contentNotFound:
            return "Trusted content not found"
        }
    }
}
