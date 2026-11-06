// MARK: - CoreKit/Realtime/RealtimeAuthDelegate.swift
//
// Module  : CoreKit
// Rôle    : Contrat pour le rafraîchissement de token sur connexion vivante.
//           DIFFÉRENT du token refresh HTTP : en HTTP on refresh entre deux requêtes.
//           En realtime, la connexion est ouverte et le JWT expire PENDANT la session.
//           Il faut ré-authentifier sans couper la connexion.
//
// Design  : Le RealtimeClient détecte l'approche de l'expiration (timer proactif)
//           et appelle le delegate pour obtenir un nouveau token.
//           Le delegate est implémenté dans l'App Target (bridge vers AuthKit).
//
// Flow    :
//   1. RealtimeClient détecte : token expire dans < tokenRefreshThreshold
//   2. Appelle delegate.realtimeClientNeedsToken()
//   3. Le delegate appelle AuthKit.tokenManager.refreshToken()
//   4. RealtimeClient ré-authentifie sur la connexion existante
//      (MQTT 5 AUTH, ou WS message d'auth)
//   5. Si échec → déconnexion .tokenExpired → cycle de reconnexion

import Foundation

// MARK: - RealtimeAuthDelegate

/// Delegate pour la gestion de l'authentification temps réel.
///
/// Implémenté dans l'App Target comme bridge entre RealtimeKit et AuthKit.
/// RealtimeKit ne connaît pas AuthKit — il reçoit un token string.
///
/// ```swift
/// // App Target — DependencyContainer
/// final class RealtimeAuthBridge: RealtimeAuthDelegate {
///     private let tokenManager: any TokenManagerProtocol
///
///     var tokenRefreshThreshold: TimeInterval { 60 }  // refresh 60s avant expiry
///
///     func realtimeClientNeedsToken() async throws -> RealtimeCredentials {
///         let jwt = try await tokenManager.validToken()
///         return RealtimeCredentials(token: jwt.rawValue, userId: jwt.userId)
///     }
///
///     func realtimeClientDidFailAuthentication(error: RealtimeError) {
///         // Poster un event pour forcer le re-login si nécessaire
///         EventBus.shared.emit(AuthenticationRequired())
///     }
/// }
/// ```
public protocol RealtimeAuthDelegate: Sendable {

    /// Appelé par le RealtimeClient quand un token valide est nécessaire.
    ///
    /// Appelé :
    /// - Au moment du connect initial
    /// - Quand le token courant approche de l'expiration (proactif)
    /// - Quand le broker rejette le token courant (réactif)
    ///
    /// - Returns: Les credentials avec le nouveau token.
    /// - Throws: Si le refresh échoue (ex: refresh token expiré → logout nécessaire).
    func realtimeClientNeedsToken() async throws -> RealtimeCredentials

    /// Durée avant l'expiration à laquelle déclencher le refresh proactif.
    ///
    /// Ex: `60` → le refresh est déclenché 60 secondes avant l'expiration du JWT.
    /// Valeur recommandée : entre 30s et 120s selon la durée de vie du token.
    var tokenRefreshThreshold: TimeInterval { get }

    /// Appelé quand l'authentification échoue de manière irrécupérable.
    ///
    /// L'implémentation peut émettre un événement via EventBus
    /// pour déclencher un re-login au niveau app.
    ///
    /// - Parameter error: L'erreur d'authentification.
    func realtimeClientDidFailAuthentication(error: RealtimeError) async
}

// MARK: - Default Implementations

extension RealtimeAuthDelegate {

    /// Threshold par défaut : 60 secondes avant expiration.
    public var tokenRefreshThreshold: TimeInterval { 60 }

    /// Par défaut, ne fait rien au failure.
    /// L'App Target override pour émettre un event de re-login.
    public func realtimeClientDidFailAuthentication(error: RealtimeError) async {
        // Default no-op — overridden by App Target implementation.
    }
}

// MARK: - RealtimeCredentials

/// Credentials pour l'authentification temps réel.
///
/// Porte le token JWT et l'identité utilisateur.
/// Passé au transport qui le traduit dans son format natif
/// (MQTT username/password, WS auth header, etc.).
public struct RealtimeCredentials: Sendable {

    /// Token JWT ou Bearer token.
    public let token: String

    /// Identifiant de l'utilisateur (extrait du JWT ou fourni séparément).
    public let userId: String?

    /// Timestamp d'expiration du token (pour le refresh proactif).
    /// `nil` si inconnu — le refresh sera déclenché uniquement par le broker reject.
    public let expiresAt: Date?

    /// Metadata additionnels pour l'authentification (headers custom, scopes).
    public let metadata: [String: String]

    // MARK: - Init

    public init(
        token: String,
        userId: String? = nil,
        expiresAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.token = token
        self.userId = userId
        self.expiresAt = expiresAt
        self.metadata = metadata
    }

    /// `true` si le token va expirer dans le threshold donné.
    public func isExpiringSoon(threshold: TimeInterval, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= threshold
    }

    /// `true` si le token est déjà expiré.
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}
