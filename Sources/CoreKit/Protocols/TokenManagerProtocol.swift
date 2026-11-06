//
//  TokenManagerProtocols.swift
//  CoreKit
//
//  Contrats purs — aucune logique, aucun type concret.
//  Implémentations dans InfrastructureKit (voir TokenManager.swift).
//

import Foundation

// MARK: - TokenManagerProtocol

/// Contrat pour la gestion des tokens d'authentification principaux de l'app
/// (login, profil, wallet, etc.).
///
/// ⚠️ Volontairement NON lié à `ChatTokenManagerProtocol` par héritage.
/// Les deux protocoles sont indépendants pour empêcher au compile-time
/// qu'une instance chat soit injectée là où l'auth principale est attendue
/// (et inversement), même si les deux ont la même forme.
public protocol TokenManagerProtocol: AnyObject, Sendable {

    // MARK: - Persistance

    /// Sauvegarde atomique des tokens. En cas d'échec partiel, rollback complet.
    func saveTokens(
        accessToken: String,
        accessTokenExpiration: Date,
        refreshToken: String,
        refreshTokenExpiration: Date
    ) async throws

    func clearTokens() async throws

    // MARK: - Lecture

    /// Retourne l'access token courant, ou `nil` si absent/corrompu.
    func getAccessToken() async throws -> String?

    /// Retourne le refresh token courant, ou `nil` si absent/corrompu.
    func getRefreshToken() async throws -> String?

    /// `true` si l'access token existe et n'est pas expiré.
    func hasValidAccessToken() async -> Bool

    /// `true` si le refresh token existe et n'est pas expiré.
    func hasValidRefreshToken() async -> Bool
}

// MARK: - ChatTokenManagerProtocol

/// Contrat pour la gestion des tokens dédiés au module Chat.
///
/// ⚠️ TEMPORAIRE — usage dev uniquement le temps que le backend chat
/// utilise son propre système d'auth. En production, ce protocole et
/// son implémentation seront supprimés ; le module Chat consommera
/// alors directement `TokenManagerProtocol`.
///
/// Ne PAS faire hériter ce protocole de `TokenManagerProtocol`
/// (voir note de sécurité de typage ci-dessus).
public protocol ChatTokenManagerProtocol: AnyObject, Sendable {

    // MARK: - Persistance

    func saveTokens(
        accessToken: String,
        accessTokenExpiration: Date,
        refreshToken: String,
        refreshTokenExpiration: Date
    ) async throws

    func clearTokens() async throws

    // MARK: - Lecture

    func getAccessToken() async throws -> String?

    func getRefreshToken() async throws -> String?

    func hasValidAccessToken() async -> Bool

    func hasValidRefreshToken() async -> Bool
}
