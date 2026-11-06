//
//  KeyChainStorageProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//

import Foundation

/// Niveau d'accessibilité des items Keychain.
///
/// Mappe directement vers les constantes `kSecAttrAccessible`.
/// `.afterFirstUnlockThisDeviceOnly` est recommandé pour les tokens —
/// disponible après le premier déverrouillage, même en background,
/// et non transféré lors d'une sauvegarde/migration.
///
    public enum KeychainAccessibility: Sendable {
        case whenUnlocked
        case whenUnlockedThisDeviceOnly
        case afterFirstUnlock
        case afterFirstUnlockThisDeviceOnly
    }

/// Contrat de stockage sécurisé via Keychain.
///
/// Utilise des clés `String` génériques — chaque module définit
/// ses propres constantes de clés (ex: `KeychainKey` enum dans l'app).
///
/// Supporte String, Data et Codable pour couvrir tous les cas d'usage.
public protocol KeychainStoreProtocol: Sendable {

    // MARK: - String
    func saveString(_ value: String, forKey key: String) async throws
    func getString(forKey key: String) async throws -> String?

    // MARK: - Data
    func saveData(_ data: Data, forKey key: String) async throws
    func getData(forKey key: String) async throws -> Data?

    // MARK: - Codable
    func saveCodable<T: Codable & Sendable>(_ value: T, forKey key: String) async throws
    func getCodable<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T?

    // MARK: - Delete
    func remove(forKey key: String) async throws
    func removeAll() async throws
}


