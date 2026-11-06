//
//  DatabaseEncryption.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Encryption/DatabaseEncryption.swift      │
// │                                                              │
// │  Responsabilités :                                           │
// │    - Générer et stocker une clé AES-256 par namespace        │
// │      dans le Keychain (jamais sur disque en clair)           │
// │    - Appliquer FileProtection sur les fichiers store         │
// │    - Fournir encrypt/decrypt pour le chiffrement colonne     │
// │                                                              │
// │  Appelé par les engines qui en ont besoin.                   │
// │  Indépendant de la technologie DB.                           │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import Security
import CryptoKit
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseEncryptionManager
// ─────────────────────────────────────────────────────────────

public actor DatabaseEncryptionManager {

    public static let shared = DatabaseEncryptionManager()
    private let keychain = DatabaseKeychain()
    private init() {}

    // ─────────────────────────────────────────────────────────
    // MARK: Clé par namespace
    // ─────────────────────────────────────────────────────────

    /// Retourne la clé AES-256 du namespace.
    /// La génère et la stocke dans le Keychain si elle n'existe pas encore.
    /// Attributs Keychain :
    ///   - kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ///     → accessible après le premier déverrouillage, même en background
    ///   - kSecAttrSynchronizable: false
    ///     → jamais synchronisée sur iCloud
    public func encryptionKey(for namespace: String) throws -> Data {
        let keychainID = "com.superapp.db.key.\(namespace)"
        if let existing = try keychain.read(keychainID) { return existing }

        let key  = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try keychain.write(keychainID, data: data)
        return data
    }

    /// Supprime la clé → les données du namespace deviennent illisibles.
    /// Équivalent d'un effacement sécurisé sans supprimer les fichiers.
    public func deleteKey(for namespace: String) throws {
        try keychain.delete("com.superapp.db.key.\(namespace)")
    }

    // ─────────────────────────────────────────────────────────
    // MARK: FileProtection iOS
    // ─────────────────────────────────────────────────────────

    /// Applique `.completeUnlessOpen` au fichier store, à ses satellites et au
    /// dossier qui les contient.
    ///
    /// Il n'y a **pas** de chiffrement du fichier entier (pas de SQLCipher) : la
    /// protection au repos est celle de l'OS, plus le chiffrement colonne
    /// ci-dessous pour les champs qui l'utilisent (B29).
    ///
    /// SQLite nomme ses satellites par **suffixe** — `<store>-wal`, `-shm`,
    /// `-journal` —, pas par extension : l'ancienne boucle visait `<store>.wal`,
    /// qui n'existe pas. Et ils naissent après l'ouverture : protéger le dossier
    /// (dédié, `StorageKit/Database`) leur fait hériter la classe à la création.
    public func applyFileProtection(to storeURL: URL) {
        let attrs: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUnlessOpen
        ]
        let fileManager = FileManager.default
        for path in Self.protectionTargets(for: storeURL, fileExists: fileManager.fileExists(atPath:)) {
            try? fileManager.setAttributes(attrs, ofItemAtPath: path)
        }
        Self.excludeFromBackup(storeURL.deletingLastPathComponent())
    }

    /// Politique de sauvegarde PROVISOIRE (CHAT-FE-SDK-W360-B13, F-05) : la base locale n'entre
    /// ni dans une sauvegarde iCloud ni dans celle d'un ordinateur. Le serveur reste la source ;
    /// après une restauration, l'historique revient par resynchronisation. Les fichiers déposés
    /// ici (brouillons, file d'envoi, repères de synchro) ne suivent pas non plus sur un nouvel
    /// appareil. À confirmer ou remplacer par la décision de rétention de Victoire (B13).
    /// Les médias sont dans `Caches`, que iOS exclut déjà.
    static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Chemins à protéger : le dossier, le store, puis les satellites présents.
    static func protectionTargets(for storeURL: URL, fileExists: (String) -> Bool) -> [String] {
        let suffixed = sqliteSatelliteSuffixes.map { storeURL.path + $0 }
        let extended = ["lock", "note", "management"].map { storeURL.appendingPathExtension($0).path }
        return [storeURL.deletingLastPathComponent().path, storeURL.path]
            + (suffixed + extended).filter(fileExists)
    }

    /// Suffixes des fichiers que SQLite crée à côté du store.
    static let sqliteSatelliteSuffixes = ["-wal", "-shm", "-journal"]

    // ─────────────────────────────────────────────────────────
    // MARK: Chiffrement colonne (AES-256 GCM)
    // ─────────────────────────────────────────────────────────

    /// Chiffre une valeur sensible avant stockage JSON.
    /// Utilisé pour les champs ultra-sensibles : IBAN, tokens, numéros de carte.
    /// Le résultat est du Data opaque stocké dans le JSON de l'entité.
    public func encrypt(_ plaintext: Data, namespace: String) throws -> Data {
        let keyData = try encryptionKey(for: namespace)
        let key     = SymmetricKey(data: keyData)
        let sealed  = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw DatabaseError.encryptionFailed(
                underlying: NSError(domain: "AES.GCM", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "combined nil"])
            )
        }
        return combined
    }

    /// Déchiffre une valeur préalablement chiffrée par `encrypt`.
    public func decrypt(_ ciphertext: Data, namespace: String) throws -> Data {
        let keyData = try encryptionKey(for: namespace)
        let key     = SymmetricKey(data: keyData)
        let sealed  = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealed, using: key)
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseKeychain — wrapper Keychain minimal
// ─────────────────────────────────────────────────────────────

private struct DatabaseKeychain: Sendable {

    func read(_ key: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrAccount:    key,
            kSecReturnData:     true,
            kSecMatchLimit:     kSecMatchLimitOne,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:      return result as? Data
        case errSecItemNotFound: return nil
        default:
            throw DatabaseError.encryptionFailed(
                underlying: NSError(domain: NSOSStatusErrorDomain, code: -1)
            )
        }
    }

    func write(_ key: String, data: Data) throws {
        try? delete(key)
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        key,
            kSecValueData:          data,
            kSecAttrAccessible:     kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable: false,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DatabaseError.encryptionFailed(
                underlying: NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            )
        }
    }

    func delete(_ key: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DatabaseError.encryptionFailed(
                underlying: NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            )
        }
    }
}
