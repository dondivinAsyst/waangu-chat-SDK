import Foundation
import CryptoKit
import Security
import WaanguCoreKit

public final class FieldEncryptionService: FieldEncryptionServiceProtocol {

    public static let shared = FieldEncryptionService()

    private let keychainTag = "com.waangu.chat.fieldEncryptionKey"
    private var cachedKey: SymmetricKey?

    private init() {}

    // MARK: - String Encryption

    public func encrypt(_ plaintext: String) -> String {
        guard !plaintext.isEmpty else { return plaintext }
        do {
            let key = try getOrCreateKey()
            let data = Data(plaintext.utf8)
            let sealed = try AES.GCM.seal(data, using: key)
            return sealed.combined!.base64EncodedString()
        } catch {
            #if DEBUG
            print("FieldEncryption encrypt failed: \(error)")
            #endif
            return plaintext
        }
    }

    public func decrypt(_ ciphertext: String) -> String {
        guard !ciphertext.isEmpty else { return ciphertext }
        do {
            let key = try getOrCreateKey()
            guard let data = Data(base64Encoded: ciphertext) else { return ciphertext }
            let box = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(box, using: key)
            return String(decoding: decrypted, as: UTF8.self)
        } catch {
            return ciphertext
        }
    }

    public func encryptOptional(_ plaintext: String?) -> String? {
        guard let plaintext else { return nil }
        return encrypt(plaintext)
    }

    public func decryptOptional(_ ciphertext: String?) -> String? {
        guard let ciphertext else { return nil }
        return decrypt(ciphertext)
    }

    // MARK: - Date Encryption

    public func encryptDate(_ date: Date) -> String {
        let iso = ISO8601DateFormatter().string(from: date)
        return encrypt(iso)
    }

    public func decryptDate(_ ciphertext: String, fallback: Date = Date()) -> Date {
        let decrypted = decrypt(ciphertext)
        return ISO8601DateFormatter().date(from: decrypted) ?? fallback
    }

    // MARK: - Data Encryption (for JSON-encoded binary fields like reactions)

    public func encryptData(_ data: Data) -> Data {
        do {
            let key = try getOrCreateKey()
            let sealed = try AES.GCM.seal(data, using: key)
            return sealed.combined!
        } catch {
            #if DEBUG
            print("FieldEncryption encryptData failed: \(error)")
            #endif
            return data
        }
    }

    public func decryptData(_ data: Data) -> Data {
        do {
            let key = try getOrCreateKey()
            let box = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(box, using: key)
        } catch {
            return data
        }
    }

    // MARK: - Key Management

    private func getOrCreateKey() throws -> SymmetricKey {
        if let cachedKey { return cachedKey }

        if let data = try loadKeyData() {
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try saveKeyData(keyData)
        cachedKey = key
        return key
    }

    // MARK: - Keychain Operations

    private func saveKeyData(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.securityError(status: status)
        }
    }

    private func loadKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
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
}
