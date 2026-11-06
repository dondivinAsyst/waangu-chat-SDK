//
//  TokenManager.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//  Updated: support d'un namespace de clés Keychain paramétrable
//  (auth principale vs chat — voir note DEV/PROD ci-dessous).
//

import Foundation
import WaanguCoreKit
import WaanguStorageKit

// MARK: - Token Keychain Namespace

/// Regroupe les clés Keychain utilisées par une instance de `TokenManager`.
///
/// Permet à une même implémentation de gérer plusieurs jeux de tokens
/// isolés (auth principale, chat, etc.) sans dupliquer la logique.
public struct TokenKeychainKeys: Sendable {
    let accessToken: String
    let accessTokenExpiration: String
    let refreshToken: String
    let refreshTokenExpiration: String

    public init(
        accessToken: String,
        accessTokenExpiration: String,
        refreshToken: String,
        refreshTokenExpiration: String
    ) {
        self.accessToken = accessToken
        self.accessTokenExpiration = accessTokenExpiration
        self.refreshToken = refreshToken
        self.refreshTokenExpiration = refreshTokenExpiration
    }

    /// Namespace de l'auth principale de l'app. Reste en production.
    public static let auth = TokenKeychainKeys(
        accessToken: "auth.accessToken",
        accessTokenExpiration: "auth.accessTokenExpiration",
        refreshToken: "auth.refreshToken",
        refreshTokenExpiration: "auth.refreshTokenExpiration"
    )

    /// Namespace des tokens Chat.
    ///
    /// ⚠️ TEMPORAIRE — DEV UNIQUEMENT.
    /// À supprimer en production avec l'enregistrement DI correspondant
    /// (voir composition root). Le module Chat basculera alors sur `.auth`.
    public static let chat = TokenKeychainKeys(
        accessToken: "chat.accessToken",
        accessTokenExpiration: "chat.accessTokenExpiration",
        refreshToken: "chat.refreshToken",
        refreshTokenExpiration: "chat.refreshTokenExpiration"
    )
}

// MARK: - TokenManager

/// Implémentation concrète de `TokenManagerProtocol` et `ChatTokenManagerProtocol`.
///
/// Persiste les tokens dans le Keychain via `KeychainStoreProtocol` (StorageKit)
/// et maintient un cache mémoire pour éviter des accès Keychain répétés.
///
/// Une instance = un namespace de clés = un jeu de tokens isolé.
/// Pour gérer auth principale + chat en parallèle, instancier deux
/// `TokenManager` distincts (voir composition root) — jamais partager
/// une seule instance entre les deux usages.
///
/// Garanties :
///   - Thread-safe (actor)
///   - Écriture atomique : si un save échoue partiellement, rollback complet
///   - Données corrompues → nettoyage automatique
public actor TokenManager {

    private let keychain: any KeychainStoreProtocol
    
    private let keys: TokenKeychainKeys
    
    private struct CachedTokens {
        let accessToken: String
        let accessExpiration: Date
        let refreshToken: String
        let refreshExpiration: Date
    }

    private var cache: CachedTokens?

    // MARK: - Init

    /// - Parameters:
    ///   - keychain: Store Keychain configuré pour l'app.
    ///     Typiquement `KeychainStore(serviceName: "com.waangu.driver")`.
    ///   - keys: Namespace de clés Keychain. `.auth` par défaut.
    ///     Utiliser `.chat` pour l'instance dédiée au module Chat (dev uniquement).
    public init(keychain: any KeychainStoreProtocol, keys: TokenKeychainKeys = .auth) {
        self.keychain = keychain
        self.keys = keys
    }

    // MARK: - Save

    public func saveTokens(
        accessToken: String,
        accessTokenExpiration: Date,
        refreshToken: String,
        refreshTokenExpiration: Date
    ) async throws {
        let accessExpStr  = DateFormatterProvider.iso8601String(from: accessTokenExpiration)
        let refreshExpStr = DateFormatterProvider.iso8601String(from: refreshTokenExpiration)

        do {
            try await keychain.saveString(accessToken, forKey: keys.accessToken)
            try await keychain.saveString(accessExpStr, forKey: keys.accessTokenExpiration)
            try await keychain.saveString(refreshToken, forKey: keys.refreshToken)
            try await keychain.saveString(refreshExpStr, forKey: keys.refreshTokenExpiration)
        } catch {
            try? await rollbackAllKeys()
            cache = nil
            throw error
        }

        cache = CachedTokens(
            accessToken: accessToken,
            accessExpiration: accessTokenExpiration,
            refreshToken: refreshToken,
            refreshExpiration: refreshTokenExpiration
        )
    }

    // MARK: - Read

    public func getAccessToken() async throws -> String? {
        try await resolveTokens()?.accessToken
    }

    public func getRefreshToken() async throws -> String? {
        try await resolveTokens()?.refreshToken
    }

    // MARK: - Validation

    public func hasValidAccessToken() async -> Bool {
        guard let tokens = try? await resolveTokens() else { return false }
        return tokens.accessExpiration > Date()
    }

    public func hasValidRefreshToken() async -> Bool {
        guard let tokens = try? await resolveTokens() else { return false }
        return tokens.refreshExpiration > Date()
    }

    // MARK: - Clear

    public func clearTokens() async throws {
        try await rollbackAllKeys()
        cache = nil
    }

    // MARK: - Private

    private func resolveTokens() async throws -> CachedTokens? {
        if let cached = cache { return cached }
        guard let loaded = try await loadFromKeychain() else { return nil }
        cache = loaded
        return loaded
    }

    private func loadFromKeychain() async throws -> CachedTokens? {
        guard
            let accessToken    = try await keychain.getString(forKey: keys.accessToken),
            let accessExpStr   = try await keychain.getString(forKey: keys.accessTokenExpiration),
            let refreshToken   = try await keychain.getString(forKey: keys.refreshToken),
            let refreshExpStr  = try await keychain.getString(forKey: keys.refreshTokenExpiration)
        else {
            return nil
        }

        guard
            let accessExp  = DateFormatterProvider.iso8601Date(from: accessExpStr),
            let refreshExp = DateFormatterProvider.iso8601Date(from: refreshExpStr)
        else {
            await AppLogger.shared.log(
                "TokenManager: corrupted expiration dates — clearing tokens",
                level: .warning
            )
            try? await clearTokens()
            return nil
        }

        return CachedTokens(
            accessToken: accessToken,
            accessExpiration: accessExp,
            refreshToken: refreshToken,
            refreshExpiration: refreshExp
        )
    }

    private func rollbackAllKeys() async throws {
        try await keychain.remove(forKey: keys.accessToken)
        try await keychain.remove(forKey: keys.accessTokenExpiration)
        try await keychain.remove(forKey: keys.refreshToken)
        try await keychain.remove(forKey: keys.refreshTokenExpiration)
    }
}

// MARK: - Protocol Conformances
extension TokenManager: TokenManagerProtocol {}
extension TokenManager: ChatTokenManagerProtocol {}
