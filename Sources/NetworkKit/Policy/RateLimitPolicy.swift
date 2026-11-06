// MARK: - NetworkKit/Policy/RateLimitPolicy.swift

import Foundation

/// Politique de rate limiting par endpoint.
/// Appliquée par `RateLimiterServiceImpl` avant chaque requête.
public struct RateLimitPolicy: Sendable {

    /// Nombre maximum de requêtes autorisées dans la fenêtre.
    public let maxRequests: Int

    /// Durée de la fenêtre glissante en secondes.
    public let perSeconds: TimeInterval

    public init(maxRequests: Int, perSeconds: TimeInterval) {
        self.maxRequests = maxRequests
        self.perSeconds = perSeconds
    }

    // MARK: - Presets

    /// Aucune limitation — `.max` court-circuite le rate limiter.
    public static let none    = RateLimitPolicy(maxRequests: .max, perSeconds: 1)

    /// 1 requête/seconde — pour les endpoints très sensibles (OTP, refresh token).
    public static let strict  = RateLimitPolicy(maxRequests: 1, perSeconds: 1)

    /// 5 requêtes/seconde — profil standard.
    public static let standard = RateLimitPolicy(maxRequests: 5, perSeconds: 1)

    /// 10 requêtes/seconde — pour les endpoints lecture non-critiques.
    public static let relaxed  = RateLimitPolicy(maxRequests: 10, perSeconds: 1)
}
