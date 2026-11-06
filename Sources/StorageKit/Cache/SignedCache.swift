import Foundation
import WaanguCoreKit
import CryptoKit

/// Signed cache storage to prevent tampering
/// Uses HMAC-SHA256 for integrity verification
public actor SignedCache {
    
    public static let shared = SignedCache()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var signingKey: SymmetricKey?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
        let cachesPath = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cachesPath.appendingPathComponent("SignedCache", isDirectory: true)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Configuration
    
    /// Set the signing key for cache integrity
    public func setSigningKey(_ key: Data) {
        self.signingKey = SymmetricKey(data: key)
    }
    
    /// Set signing key from base64 string
    public func setSigningKey(base64: String) throws {
        guard let data = Data(base64Encoded: base64) else {
            throw CacheError.invalidSigningKey
        }
        self.signingKey = SymmetricKey(data: data)
    }
    
    // MARK: - Cache Operations
    
    /// Store value in signed cache
    public func set<T: Codable & Sendable>(
        _ value: T,
        forKey key: String,
        ttl: TimeInterval? = nil
    ) throws {
        guard let signingKey = signingKey else {
            throw CacheError.signingKeyNotConfigured
        }
        
        // Encode value
        let valueData = try encoder.encode(value)
        
        // Create cache entry
        let expiresAt = ttl.map { Date().addingTimeInterval($0) }
        let entry = CacheEntry(
            key: key,
            data: valueData,
            createdAt: Date(),
            expiresAt: expiresAt
        )
        
        // Serialize entry
        let entryData = try encoder.encode(entry)
        
        // Compute signature
        let signature = HMAC<SHA256>.authenticationCode(for: entryData, using: signingKey)
        
        // Create signed entry
        let signedEntry = SignedCacheEntry(
            entry: entry,
            signature: Data(signature)
        )
        
        // Save to disk
        let fileURL = cacheFileURL(forKey: key)
        let signedData = try encoder.encode(signedEntry)
        try signedData.write(to: fileURL, options: .atomic)
    }
    
    /// Retrieve and verify value from signed cache
    public func get<T: Codable & Sendable>(forKey key: String, as type: T.Type) throws -> T? {
        guard let signingKey = signingKey else {
            throw CacheError.signingKeyNotConfigured
        }
        
        let fileURL = cacheFileURL(forKey: key)
        
        // Check if file exists
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        // Read signed entry
        let signedData = try Data(contentsOf: fileURL)
        let signedEntry = try decoder.decode(SignedCacheEntry.self, from: signedData)
        
        // Verify signature
        let entryData = try encoder.encode(signedEntry.entry)
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: entryData, using: signingKey)
        
        guard Data(expectedSignature) == signedEntry.signature else {
            // Signature mismatch - cache tampered!
            try? fileManager.removeItem(at: fileURL)
            throw CacheError.signatureVerificationFailed(key: key)
        }
        
        // Check expiration
        if let expiresAt = signedEntry.entry.expiresAt, expiresAt < Date() {
            // Expired - remove and return nil
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        
        // Decode value
        let value = try decoder.decode(type, from: signedEntry.entry.data)
        return value
    }
    
    /// Remove value from cache
    public func remove(forKey key: String) throws {
        let fileURL = cacheFileURL(forKey: key)
        try fileManager.removeItem(at: fileURL)
    }
    
    /// Check if key exists and is valid
    public func exists(forKey key: String) async -> Bool {
        do {
            let _: Data? = try get(forKey: key, as: Data.self)
            return true
        } catch {
            return false
        }
    }
    
    /// Clear all cache
    public func clearAll() throws {
        let files = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        for file in files {
            try fileManager.removeItem(at: file)
        }
    }
    
    /// Clear expired entries
    public func clearExpired() throws {
        let files = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        for file in files {
            do {
                let signedData = try Data(contentsOf: file)
                let signedEntry = try decoder.decode(SignedCacheEntry.self, from: signedData)
                
                if let expiresAt = signedEntry.entry.expiresAt, expiresAt < Date() {
                    try fileManager.removeItem(at: file)
                }
            } catch {
                // Invalid entry, remove it
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    /// Get cache statistics
    public func getStats() throws -> CacheStats {
        let files = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        var totalSize: Int64 = 0
        var validEntries = 0
        var expiredEntries = 0
        var corruptedEntries = 0
        
        for file in files {
            // Get file size
            if let resources = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let size = resources.fileSize {
                totalSize += Int64(size)
            }
            
            // Check entry validity
            do {
                let signedData = try Data(contentsOf: file)
                let signedEntry = try decoder.decode(SignedCacheEntry.self, from: signedData)
                
                if let expiresAt = signedEntry.entry.expiresAt, expiresAt < Date() {
                    expiredEntries += 1
                } else {
                    validEntries += 1
                }
            } catch {
                corruptedEntries += 1
            }
        }
        
        return CacheStats(
            totalEntries: files.count,
            validEntries: validEntries,
            expiredEntries: expiredEntries,
            corruptedEntries: corruptedEntries,
            totalSizeBytes: totalSize
        )
    }
    
    // MARK: - Private Helpers
    
    private func cacheFileURL(forKey key: String) -> URL {
        let filename = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return cacheDirectory.appendingPathComponent("\(filename).cache")
    }
}

// MARK: - Models

private struct CacheEntry: Codable {
    let key: String
    let data: Data
    let createdAt: Date
    let expiresAt: Date?
}

private struct SignedCacheEntry: Codable {
    let entry: CacheEntry
    let signature: Data
}

public struct CacheStats: Sendable {
    public let totalEntries: Int
    public let validEntries: Int
    public let expiredEntries: Int
    public let corruptedEntries: Int
    public let totalSizeBytes: Int64
    
    public var totalSizeMB: Double {
        Double(totalSizeBytes) / 1024 / 1024
    }
    
    public var hasCorruption: Bool {
        corruptedEntries > 0
    }
}

// MARK: - Errors

public enum CacheError: Error, LocalizedError {
    case signingKeyNotConfigured
    case invalidSigningKey
    case signatureVerificationFailed(key: String)
    case entryNotFound(key: String)
    case entryExpired(key: String)
    
    public var errorDescription: String? {
        switch self {
        case .signingKeyNotConfigured:
            return "Cache signing key not configured"
        case .invalidSigningKey:
            return "Invalid signing key format"
        case .signatureVerificationFailed(let key):
            return "Cache signature verification failed for key: \(key)"
        case .entryNotFound(let key):
            return "Cache entry not found: \(key)"
        case .entryExpired(let key):
            return "Cache entry expired: \(key)"
        }
    }
}

// MARK: - Usage Examples

/*
 Example 1: Configure signing key (on app launch)
 
 // Get signing key from secure configuration
 let cacheKey = try await configService.getCacheSigningKey()
 try await SignedCache.shared.setSigningKey(base64: cacheKey)
 
 Example 2: Store data in signed cache
 
 struct UserProfile: Codable, Sendable {
     let id: String
     let name: String
     let email: String
 }
 
 let profile = UserProfile(id: "123", name: "John", email: "john@example.com")
 
 // Store with 1 hour TTL
 try await SignedCache.shared.set(
     profile,
     forKey: "user_profile_123",
     ttl: 3600
 )
 
 Example 3: Retrieve and verify cached data
 
 do {
     if let profile = try await SignedCache.shared.get(
         forKey: "user_profile_123",
         as: UserProfile.self
     ) {
         // Cache hit and signature verified
         print("Cached profile: \(profile.name)")
     } else {
         // Cache miss or expired
         let profile = try await fetchProfileFromAPI()
         try await SignedCache.shared.set(profile, forKey: "user_profile_123", ttl: 3600)
     }
     
 } catch CacheError.signatureVerificationFailed(let key) {
     // CRITICAL: Cache tampered!
     await AuditBreadcrumb.shared.record(
         action: .securityViolation,
         category: .security,
         metadata: [
             "violation": "cache_tampering",
             "cache_key": key
         ],
         severity: .critical
     )
     
     // Remove corrupted cache and fetch fresh data
     try? await SignedCache.shared.remove(forKey: key)
     let profile = try await fetchProfileFromAPI()
     try await SignedCache.shared.set(profile, forKey: key, ttl: 3600)
 }
 
 Example 4: Cache maintenance
 
 // Clear expired entries periodically
 try await SignedCache.shared.clearExpired()
 
 // Get cache statistics
 let stats = try await SignedCache.shared.getStats()
 print("Cache size: \(stats.totalSizeMB) MB")
 print("Valid entries: \(stats.validEntries)")
 print("Corrupted entries: \(stats.corruptedEntries)")
 
 if stats.hasCorruption {
     await AuditBreadcrumb.shared.record(
         action: .securityViolation,
         category: .security,
         metadata: ["corrupted_entries": String(stats.corruptedEntries)],
         severity: .high
     )
 }
 */
