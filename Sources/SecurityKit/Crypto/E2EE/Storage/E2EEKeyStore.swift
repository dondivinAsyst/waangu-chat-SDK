import Foundation
import CryptoKit
import Security
import WaanguCoreKit

public final class E2EEKeyStore: E2EEKeyStoreProtocol {

    public static let shared = E2EEKeyStore()

    private let keyPrefix = "com.waangu.chat.e2ee"
    private let maxSkippedKeys = 256

    // MARK: - Identity Key Pair

    public func getOrCreateIdentityKeyPair() async throws -> Curve25519.KeyAgreement.PrivateKey {
        let tag = "\(keyPrefix).identityKey"
        if let data = try loadData(forKey: tag) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try saveData(key.rawRepresentation, forKey: tag)
        return key
    }

    public func getIdentityPublicKey() async throws -> Data {
        let key = try await getOrCreateIdentityKeyPair()
        return key.publicKey.rawRepresentation
    }

    // MARK: - Signed Pre-Key

    public func getOrCreateSignedPreKey() async throws -> Curve25519.KeyAgreement.PrivateKey {
        let tag = "\(keyPrefix).signedPreKey"
        if let data = try loadData(forKey: tag) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try saveData(key.rawRepresentation, forKey: tag)
        return key
    }

    public func getSignedPreKeySignature() async throws -> Data {
        let signingTag = "\(keyPrefix).signingKey"
        let signingKey: Curve25519.Signing.PrivateKey

        if let data = try loadData(forKey: signingTag) {
            signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        } else {
            signingKey = Curve25519.Signing.PrivateKey()
            try saveData(signingKey.rawRepresentation, forKey: signingTag)
        }

        let signedPreKey = try await getOrCreateSignedPreKey()
        return try signingKey.signature(for: signedPreKey.publicKey.rawRepresentation)
    }

    // MARK: - One-Time Pre-Keys

    public func generateOneTimePreKeys(count: Int) async throws -> [Curve25519.KeyAgreement.PrivateKey] {
        var keys: [Curve25519.KeyAgreement.PrivateKey] = []
        for i in 0..<count {
            let key = Curve25519.KeyAgreement.PrivateKey()
            let tag = "\(keyPrefix).oneTimePreKey.\(i)"
            try saveData(key.rawRepresentation, forKey: tag)
            keys.append(key)
        }
        return keys
    }

    public func consumeOneTimePreKey(id: Int) async throws -> Curve25519.KeyAgreement.PrivateKey? {
        let tag = "\(keyPrefix).oneTimePreKey.\(id)"
        guard let data = try loadData(forKey: tag) else { return nil }
        try deleteData(forKey: tag)
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    // MARK: - Session Persistence

    public func saveSession(_ session: SessionState, for conversationId: String) async throws {
        let tag = "\(keyPrefix).session.\(conversationId)"
        let data = try JSONEncoder().encode(session)
        try saveData(data, forKey: tag)
    }

    public func loadSession(for conversationId: String) async throws -> SessionState? {
        let tag = "\(keyPrefix).session.\(conversationId)"
        guard let data = try loadData(forKey: tag) else { return nil }
        return try JSONDecoder().decode(SessionState.self, from: data)
    }

    public func deleteSession(for conversationId: String) async throws {
        let tag = "\(keyPrefix).session.\(conversationId)"
        try deleteData(forKey: tag)
    }

    // MARK: - Low-Level Keychain Operations

    private func saveData(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.securityError(status: status)
        }
    }

    private func loadData(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.securityError(status: status)
        }
        return item as? Data
    }

    private func deleteData(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
