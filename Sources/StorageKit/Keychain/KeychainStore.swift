//
//  KeychainStore.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import WaanguCoreKit
import Foundation
import Security

/// Implémentation thread-safe du stockage Keychain via actor.
///
/// Configurable via :
///   - `serviceName`  : isole les entrées par app/feature (kSecAttrService).
///   - `accessGroup`  : partage entre app + extensions via App Group.
///   - `accessibility` : quand les données sont accessibles (locked/unlocked).
///
/// Usage :
/// ```swift
/// let store = KeychainStore(serviceName: "com.waangu.driver")
/// try await store.saveString(token, forKey: "accessToken")
/// let token = try await store.getString(forKey: "accessToken")
/// ```
public actor KeychainStore: KeychainStoreProtocol {

    private let serviceName: String
    private let accessGroup: String?
    private let accessibility: KeychainAccessibility
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        serviceName: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .afterFirstUnlockThisDeviceOnly
    ) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
        self.accessibility = accessibility
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - String

    public func saveString(_ value: String, forKey key: String) async throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try saveRaw(data, forKey: key)
    }

    public func getString(forKey key: String) async throws -> String? {
        guard let data = try getRaw(forKey: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed(type: "String")
        }
        return string
    }

    // MARK: - Data

    public func saveData(_ data: Data, forKey key: String) async throws {
        try saveRaw(data, forKey: key)
    }

    public func getData(forKey key: String) async throws -> Data? {
        try getRaw(forKey: key)
    }

    // MARK: - Codable

    public func saveCodable<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        let data = try encoder.encode(value)
        try saveRaw(data, forKey: key)
    }

    public func getCodable<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        guard let data = try getRaw(forKey: key) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw KeychainError.decodingFailed(type: String(describing: type))
        }
    }

    // MARK: - Delete

    public func remove(forKey key: String) async throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.securityError(status: status)
        }
    }

    public func removeAll() async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.securityError(status: status)
        }
    }

    // MARK: - Private

    private func saveRaw(_ data: Data, forKey key: String) throws {
        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessibility.secAttrValue

        // Delete-then-add : Security framework n'a pas d'upsert atomique.
        SecItemDelete(baseQuery(forKey: key) as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.securityError(status: status)
        }
    }

    private func getRaw(forKey key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.securityError(status: status)
        }
        return item as? Data
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
}

extension KeychainAccessibility {
    var secAttrValue: CFString {
        switch self {
        case .whenUnlocked:                   return kSecAttrAccessibleWhenUnlocked
        case .whenUnlockedThisDeviceOnly:     return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlock:               return kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}

