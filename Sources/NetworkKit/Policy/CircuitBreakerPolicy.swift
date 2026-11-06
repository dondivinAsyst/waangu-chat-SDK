// MARK: - NetworkKit/Policy/CircuitBreakerPolicy.swift

import Foundation

// MARK: - CircuitBreakerProfile

public enum CircuitBreakerProfile: Sendable {
    case aggressive
    case standard
    case conservative
    case disabled
}

// MARK: - CircuitBreakerPolicy

public struct CircuitBreakerPolicy: Sendable {

    /// Nombre d'échecs consécutifs avant ouverture du circuit.
    public let failureThreshold: Int

    /// Délai en secondes avant tentative de réouverture (half-open).
    public let resetTimeout: TimeInterval

    /// Nombre de requêtes autorisées en half-open avant fermeture définitive.
    public let halfOpenMaxRequests: Int

    public init(
        failureThreshold: Int,
        resetTimeout: TimeInterval,
        halfOpenMaxRequests: Int
    ) {
        self.failureThreshold = failureThreshold
        self.resetTimeout = resetTimeout
        self.halfOpenMaxRequests = halfOpenMaxRequests
    }

    // MARK: - Presets

    /// Ouvre rapidement — pour les endpoints critiques (paiement, auth).
    public static let aggressive = CircuitBreakerPolicy(
        failureThreshold: 3,
        resetTimeout: 60,
        halfOpenMaxRequests: 1
    )

    /// Équilibre tolérance/protection — profil par défaut.
    public static let standard = CircuitBreakerPolicy(
        failureThreshold: 5,
        resetTimeout: 30,
        halfOpenMaxRequests: 2
    )

    /// Tolérant — pour les endpoints non-critiques (analytics, logs).
    public static let conservative = CircuitBreakerPolicy(
        failureThreshold: 8,
        resetTimeout: 15,
        halfOpenMaxRequests: 3
    )

    /// Circuit breaker désactivé — jamais d'ouverture.
    public static let disabled = CircuitBreakerPolicy(
        failureThreshold: .max,
        resetTimeout: 0,
        halfOpenMaxRequests: .max
    )

    // MARK: - Factory

    public static func from(_ profile: CircuitBreakerProfile) -> CircuitBreakerPolicy {
        switch profile {
        case .aggressive:   return .aggressive
        case .standard:     return .standard
        case .conservative: return .conservative
        case .disabled:     return .disabled
        }
    }
}
