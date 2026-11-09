//
//  RealtimeAuthBridge.swift
//  WaanguChatSDK
//
//  Created by Asyst on 6/4/26.
//  Moved from the Waangu app target into WaanguChatSDK (SDK plan, step 1.9).
//

// MARK: - WaanguChatSDK/RealtimeAuthBridge.swift
//
// Module  : WaanguChatSDK (was: App Target)
// Rôle    : Pont entre AuthKit (TokenManagerProtocol) et RealtimeKit (RealtimeAuthDelegate).
//           L'App Target est le seul endroit qui connaît les deux modules.
//
// Adapté au TokenManagerProtocol réel :
//   - pas de validToken() → on compose hasValidAccessToken() + getAccessToken()
//   - expiresAt décodé depuis le claim JWT `exp` pour le refresh proactif MQTT
//   - pas de refreshToken() explicite → l'implémentation de getAccessToken()
//     est responsable du refresh interne si le token est expiré

import Foundation
import WaanguCoreKit

// MARK: - RealtimeAuthBridge

public final class RealtimeAuthBridge: RealtimeAuthDelegate, Sendable {

    // MARK: - Dependencies

    private let tokenManager: any ChatTokenManagerProtocol
    private let eventBus: any EventBusProtocol
    /// Logs in to chat again when its session has expired; `true` when a new one was saved.
    /// `nil` keeps the old behaviour: an expired session just fails.
    private let reauthenticate: (@Sendable () async -> Bool)?

    // MARK: - Configuration

    /// 90s avant expiration → 3 retries avec backoff (2s→4s→8s)
    /// ont le temps de passer avant l'expiration réelle.
    public let tokenRefreshThreshold: TimeInterval = 90

    // MARK: - Init

    public init(
        tokenManager: any ChatTokenManagerProtocol,
        eventBus: any EventBusProtocol,
        reauthenticate: (@Sendable () async -> Bool)? = nil
    ) {
        self.tokenManager = tokenManager
        self.eventBus = eventBus
        self.reauthenticate = reauthenticate
    }

    // MARK: - RealtimeAuthDelegate

    /// Fournit un token JWT frais pour la connexion/re-auth temps réel.
    ///
    /// Flow :
    ///   1. Access token valide → l'utiliser directement
    ///   2. Access token expiré + refresh token valide → getAccessToken()
    ///      (le TokenManager gère le refresh en interne)
    ///   3. Aucun token valide → throw (force re-login)
    public func realtimeClientNeedsToken() async throws -> RealtimeCredentials {

        // Cas 1 — access token encore valide.
        if await tokenManager.hasValidAccessToken() {
            guard let token = try await tokenManager.getAccessToken() else {
                throw RealtimeError.authenticationFailed(
                    reason: "Access token is nil despite hasValidAccessToken() = true"
                )
            }
            return makeCredentials(token: token)
        }

        // Cas 2 — access token expiré, refresh token encore valide.
        // getAccessToken() est responsable du refresh interne.
        if await tokenManager.hasValidRefreshToken() {
            guard let token = try await tokenManager.getAccessToken() else {
                throw RealtimeError.tokenRefreshFailed(
                    underlyingReason: "getAccessToken() returned nil after refresh attempt"
                )
            }
            return makeCredentials(token: token)
        }

        // Cas 3 — aucun token valide → session expirée. Une nouvelle connexion au chat,
        // si l'hôte en fournit une, en crée une autre sans que l'utilisateur ne fasse rien.
        if let reauthenticate, await reauthenticate(),
           await tokenManager.hasValidAccessToken(),
           let token = try await tokenManager.getAccessToken() {
            return makeCredentials(token: token)
        }
        throw RealtimeError.authenticationFailed(
            reason: "No valid token available — session expired"
        )
    }

    /// Appelé quand l'auth temps réel échoue définitivement
    /// (tous les retries épuisés, broker rejette systématiquement).
    ///
    /// Émet un événement EventBus pour déclencher le re-login.
    /// FeatureAuth écoute cet événement.
    public func realtimeClientDidFailAuthentication(error: RealtimeError) async {
        #if DEBUG
        print("[App] Realtime auth failed permanently: \(error.localizedDescription)")
        #endif
//        await eventBus.emit(RealtimeAuthFailedEvent(error: error))
    }

    // MARK: - Private

    private func makeCredentials(token: String) -> RealtimeCredentials {
        RealtimeCredentials(
            token: token,
            userId: nil,
            expiresAt: Self.jwtExpirationDate(from: token)
        )
    }

    /// Decodes the `exp` claim from a JWT without verifying the signature.
    private static func jwtExpirationDate(from token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - base64.count % 4
        if pad < 4 {
            base64.append(String(repeating: "=", count: pad))
        }

        guard
            let data = Data(base64Encoded: base64),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let exp: TimeInterval?
        if let value = json["exp"] as? TimeInterval {
            exp = value
        } else if let value = json["exp"] as? Int {
            exp = TimeInterval(value)
        } else if let value = json["exp"] as? Double {
            exp = value
        } else {
            exp = nil
        }

        guard let exp else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

// MARK: - RealtimeAuthFailedEvent

/// Événement émis quand l'auth temps réel échoue définitivement.
/// FeatureAuth écoute cet événement et redirige vers l'écran de login.
public struct RealtimeAuthFailedEvent: Sendable {
    public let error: RealtimeError
    public let timestamp: Date = Date()

    public init(error: RealtimeError) {
        self.error = error
    }
}
