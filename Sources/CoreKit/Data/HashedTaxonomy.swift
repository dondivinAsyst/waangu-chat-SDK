//
//  HashedTaxonomy.swift
//  CoreKit
//
//  Hash-based integrity verification for shared taxonomies

import Foundation
import CryptoKit

public actor HashedTaxonomy {
    
    public static let shared = HashedTaxonomy()
    
    private var taxonomies: [String: TaxonomyEntry] = [:]
    private var verificationKey: SymmetricKey?
    
    private init() {}
    
    // MARK: - Configuration
    
    public func setVerificationKey(base64: String) throws {
        guard let data = Data(base64Encoded: base64) else {
            throw TaxonomyError.invalidKey
        }
        self.verificationKey = SymmetricKey(data: data)
    }
    
    // MARK: - Register Taxonomy
    
    public func register<T: Codable & Hashable>(
        _ taxonomy: T,
        forKey key: String,
        version: String = "1.0"
    ) async throws {
        guard let verificationKey = verificationKey else {
            throw TaxonomyError.keyNotConfigured
        }
        
        // Serialize taxonomy
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(taxonomy)
        
        // Generate hash
        let hash = HMAC<SHA256>.authenticationCode(for: data, using: verificationKey)
        let hashString = Data(hash).base64EncodedString()
        
        // Store entry
        let entry = TaxonomyEntry(
            key: key,
            version: version,
            data: data,
            hash: hashString,
            registeredAt: Date()
        )
        
        taxonomies[key] = entry
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "action": "taxonomy_registered",
                "key": key,
                "version": version,
                "hash": String(hashString.prefix(16))
            ],
            severity: .info
        )
    }
    
    // MARK: - Verify Taxonomy
    
    public func verify<T: Codable & Hashable>(
        _ taxonomy: T,
        forKey key: String
    ) async throws -> VerificationResult {
        guard let verificationKey = verificationKey else {
            throw TaxonomyError.keyNotConfigured
        }
        
        guard let entry = taxonomies[key] else {
            throw TaxonomyError.taxonomyNotFound(key: key)
        }
        
        // Serialize incoming taxonomy
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(taxonomy)
        
        // Generate hash
        let hash = HMAC<SHA256>.authenticationCode(for: data, using: verificationKey)
        let hashString = Data(hash).base64EncodedString()
        
        // Compare hashes (constant-time)
        let isValid = constantTimeCompare(hashString, entry.hash)
        
        if !isValid {
            // CRITICAL: Taxonomy tampered!
            await AuditBreadcrumb.shared.recordSecurity(
                action: .securityViolation,
                userId: nil,
                metadata: [
                    "violation": "taxonomy_tampering",
                    "key": key,
                    "expected_hash": String(entry.hash.prefix(16)),
                    "actual_hash": String(hashString.prefix(16))
                ]
            )
            
            throw TaxonomyError.verificationFailed(key: key)
        }
        
        return VerificationResult(
            key: key,
            version: entry.version,
            isValid: true,
            verifiedAt: Date()
        )
    }
    
    // MARK: - Get Taxonomy
    
    public func get<T: Codable>(forKey key: String, as type: T.Type) throws -> T {
        guard let entry = taxonomies[key] else {
            throw TaxonomyError.taxonomyNotFound(key: key)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: entry.data)
    }
    
    // MARK: - List Taxonomies
    
    public func listAll() -> [TaxonomyInfo] {
        taxonomies.values.map { entry in
            TaxonomyInfo(
                key: entry.key,
                version: entry.version,
                hash: String(entry.hash.prefix(16)),
                registeredAt: entry.registeredAt
            )
        }
    }
    
    // MARK: - Remove Taxonomy
    
    public func remove(forKey key: String) {
        taxonomies.removeValue(forKey: key)
    }
    
    public func removeAll() {
        taxonomies.removeAll()
    }
    
    // MARK: - Helpers
    
    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        
        var result = 0
        for (charA, charB) in zip(a, b) {
            result |= Int(charA.asciiValue ?? 0) ^ Int(charB.asciiValue ?? 0)
        }
        
        return result == 0
    }
    
    // MARK: - Types
    
    public struct TaxonomyEntry {
        let key: String
        let version: String
        let data: Data
        let hash: String
        let registeredAt: Date
    }
    
    public struct TaxonomyInfo {
        public let key: String
        public let version: String
        public let hash: String
        public let registeredAt: Date
    }
    
    public struct VerificationResult {
        public let key: String
        public let version: String
        public let isValid: Bool
        public let verifiedAt: Date
    }
    
    public enum TaxonomyError: Error, LocalizedError {
        case keyNotConfigured
        case invalidKey
        case taxonomyNotFound(key: String)
        case verificationFailed(key: String)
        
        public var errorDescription: String? {
            switch self {
            case .keyNotConfigured:
                return "Taxonomy verification key not configured"
            case .invalidKey:
                return "Invalid verification key format"
            case .taxonomyNotFound(let key):
                return "Taxonomy not found: \(key)"
            case .verificationFailed(let key):
                return "Taxonomy verification failed for: \(key)"
            }
        }
    }
}

// MARK: - Common Taxonomies

public enum MessageCategory: String, Codable, Hashable, CaseIterable {
    case text
    case image
    case video
    case audio
    case location
    case contact
    case file
    case sticker
    case gif
}

public enum AIResponseType: String, Codable, Hashable, CaseIterable {
    case answer
    case suggestion
    case translation
    case summary
    case error
    case clarification
}

public enum TranslationLanguagePair: String, Codable, Hashable {
    case enToFr = "en-fr"
    case enToEs = "en-es"
    case enToDe = "en-de"
    case frToEn = "fr-en"
    case esToEn = "es-en"
    case deToEn = "de-en"
}
