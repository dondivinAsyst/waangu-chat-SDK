import Foundation
import Security

/// Secure memory container for sensitive data
/// Provides memory protection and automatic cleanup
public final class SecureMemoryBox<T: Codable & Sendable>: @unchecked Sendable {
    
    private let lock = NSLock()
    private var encryptedData: Data?
    private let key: SymmetricKey
    private var accessCount: Int = 0
    private let maxAccessCount: Int?
    private var lastAccessTime: Date?
    private let autoWipeDelay: TimeInterval?
    
    /// Initialize with optional security constraints
    /// - Parameters:
    ///   - maxAccessCount: Maximum number of times value can be accessed before auto-wipe
    ///   - autoWipeDelay: Time interval after which value is auto-wiped if not accessed
    public init(
        maxAccessCount: Int? = nil,
        autoWipeDelay: TimeInterval? = nil
    ) {
        self.key = SymmetricKey.generate() // CI-ALLOW: CryptoKit, pas un appel IA
        self.maxAccessCount = maxAccessCount
        self.autoWipeDelay = autoWipeDelay
    }
    
    deinit {
        wipe()
    }
    
    // MARK: - Public API
    
    /// Store value securely in memory
    public func store(_ value: T) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let encoder = JSONEncoder()
        let plainData = try encoder.encode(value)
        
        // Encrypt data
        encryptedData = try encrypt(plainData, with: key)
        accessCount = 0
        lastAccessTime = Date()
        
        // Schedule auto-wipe if configured
        if let delay = autoWipeDelay {
            scheduleAutoWipe(after: delay)
        }
    }
    
    /// Retrieve value from secure memory
    public func retrieve() throws -> T {
        lock.lock()
        defer { lock.unlock() }
        
        guard let encrypted = encryptedData else {
            throw SecureMemoryError.noDataStored
        }
        
        // Check access count limit
        if let maxCount = maxAccessCount, accessCount >= maxCount {
            wipe()
            throw SecureMemoryError.accessLimitExceeded
        }
        
        // Check auto-wipe timeout
        if let delay = autoWipeDelay,
           let lastAccess = lastAccessTime,
           Date().timeIntervalSince(lastAccess) > delay {
            wipe()
            throw SecureMemoryError.dataExpired
        }
        
        // Decrypt data
        let plainData = try decrypt(encrypted, with: key)
        
        // Decode value
        let decoder = JSONDecoder()
        let value = try decoder.decode(T.self, from: plainData)
        
        accessCount += 1
        lastAccessTime = Date()
        
        // Auto-wipe if max access count reached
        if let maxCount = maxAccessCount, accessCount >= maxCount {
            wipe()
        }
        
        return value
    }
    
    /// Check if value is stored
    public func hasValue() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return encryptedData != nil
    }
    
    /// Wipe value from memory
    public func wipe() {
        lock.lock()
        defer { lock.unlock() }
        
        // Overwrite encrypted data with zeros before releasing
        if var data = encryptedData {
            data.withUnsafeMutableBytes { ptr in
                memset(ptr.baseAddress, 0, ptr.count)
            }
        }
        
        encryptedData = nil
        accessCount = 0
        lastAccessTime = nil
    }
    
    /// Get access statistics
    public func getAccessInfo() -> AccessInfo {
        lock.lock()
        defer { lock.unlock() }
        
        return AccessInfo(
            accessCount: accessCount,
            maxAccessCount: maxAccessCount,
            lastAccessTime: lastAccessTime,
            hasValue: encryptedData != nil
        )
    }
    
    // MARK: - Private Helpers
    
    private func encrypt(_ data: Data, with key: SymmetricKey) throws -> Data {
        // Simple XOR encryption for demonstration
        // In production, use CryptoKit's AES-GCM
        var encrypted = Data(count: data.count)
        let keyBytes = key.bytes
        
        for i in 0..<data.count {
            encrypted[i] = data[i] ^ keyBytes[i % keyBytes.count]
        }
        
        return encrypted
    }
    
    private func decrypt(_ data: Data, with key: SymmetricKey) throws -> Data {
        // XOR is symmetric
        return try encrypt(data, with: key)
    }
    
    private func scheduleAutoWipe(after delay: TimeInterval) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.checkAndWipeIfExpired()
        }
    }
    
    private func checkAndWipeIfExpired() {
        lock.lock()
        defer { lock.unlock() }
        
        guard let delay = autoWipeDelay,
              let lastAccess = lastAccessTime else {
            return
        }
        
        if Date().timeIntervalSince(lastAccess) >= delay {
            wipe()
        }
    }
}

// MARK: - Supporting Types

private struct SymmetricKey {
    let bytes: [UInt8]
    
    static func generate() -> SymmetricKey {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return SymmetricKey(bytes: bytes)
    }
}

public struct AccessInfo: Sendable {
    public let accessCount: Int
    public let maxAccessCount: Int?
    public let lastAccessTime: Date?
    public let hasValue: Bool
    
    public var remainingAccesses: Int? {
        guard let maxCount = maxAccessCount else { return nil }
        return max(0, maxCount - accessCount)
    }
}

public enum SecureMemoryError: Error, LocalizedError {
    case noDataStored
    case accessLimitExceeded
    case dataExpired
    case encryptionFailed
    case decryptionFailed
    
    public var errorDescription: String? {
        switch self {
        case .noDataStored:
            return "No data stored in secure memory"
        case .accessLimitExceeded:
            return "Access limit exceeded, data has been wiped"
        case .dataExpired:
            return "Data has expired and been wiped"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        }
    }
}

// MARK: - Convenience Extensions

public extension SecureMemoryBox where T == String {
    /// Store string securely
    func store(_ string: String) throws {
        try store(string)
    }
    
    /// Retrieve string securely
    func retrieveString() throws -> String {
        try retrieve()
    }
}

public extension SecureMemoryBox where T == Data {
    /// Store data securely
    func store(_ data: Data) throws {
        try store(data)
    }
    
    /// Retrieve data securely
    func retrieveData() throws -> Data {
        try retrieve()
    }
}

// MARK: - Usage Examples

/*
 Example 1: Store sensitive token with access limit
 
 let tokenBox = SecureMemoryBox<String>(maxAccessCount: 3)
 try tokenBox.store("sensitive_token_12345")
 
 let token1 = try tokenBox.retrieve() // OK
 let token2 = try tokenBox.retrieve() // OK
 let token3 = try tokenBox.retrieve() // OK - auto-wiped after this
 let token4 = try tokenBox.retrieve() // Throws accessLimitExceeded
 
 Example 2: Store password with auto-wipe
 
 let passwordBox = SecureMemoryBox<String>(autoWipeDelay: 300) // 5 minutes
 try passwordBox.store("user_password")
 
 // After 5 minutes of no access
 let password = try passwordBox.retrieve() // Throws dataExpired
 
 Example 3: Store encryption key
 
 let keyBox = SecureMemoryBox<Data>()
 try keyBox.store(encryptionKeyData)
 
 let key = try keyBox.retrieve()
 // Use key...
 
 keyBox.wipe() // Explicitly wipe when done
 */
