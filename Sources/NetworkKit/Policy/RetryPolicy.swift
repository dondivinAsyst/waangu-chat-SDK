// MARK: - NetworkKit/Policy/RetryPolicy.swift

import Foundation

// MARK: - RetryStrategy

/// Stratégie générique de retry avec exponential backoff et jitter optionnel.
public struct RetryStrategy: Sendable, Equatable {

    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let jitter: Bool

    public init(
        maxRetries: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        jitter: Bool
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    /// Calcule le délai pour une tentative donnée.
    /// Exponential backoff : baseDelay × 2^attempt, plafonné à maxDelay.
    /// Full jitter si activé : délai aléatoire entre 0 et la valeur plafonnée.
    public func delay(for attempt: Int) -> TimeInterval {
        guard attempt >= 0 else { return 0 }
        let exponential = baseDelay * pow(2.0, Double(attempt))
        let capped = min(exponential, maxDelay)
        return jitter ? Double.random(in: 0...capped) : capped
    }
}

// MARK: - RetryProfile

/// Profils de retry prédéfinis.
/// Utilisé par `DeviceConfiguration` pour sélectionner la stratégie adaptée.
public enum RetryProfile: String, Sendable, CaseIterable {
    case none
    case conservative
    case standard
    case aggressive

    public func makeStrategy() -> RetryStrategy {
        switch self {
        case .none:
            return RetryStrategy(maxRetries: 0, baseDelay: 0, maxDelay: 0, jitter: false)
        case .conservative:
            return RetryStrategy(maxRetries: 2, baseDelay: 2.0, maxDelay: 30.0, jitter: true)
        case .standard:
            return RetryStrategy(maxRetries: 3, baseDelay: 1.0, maxDelay: 30.0, jitter: true)
        case .aggressive:
            return RetryStrategy(maxRetries: 5, baseDelay: 0.5, maxDelay: 60.0, jitter: true)
        }
    }
}

// MARK: - RetryStrategy presets

public extension RetryStrategy {
    static let none         = RetryProfile.none.makeStrategy()
    static let conservative = RetryProfile.conservative.makeStrategy()
    static let standard     = RetryProfile.standard.makeStrategy()
    static let aggressive   = RetryProfile.aggressive.makeStrategy()

    /// Stratégie recommandée pour MQTT — reconnexions longues avec backoff étendu.
    static let mqttDefault      = RetryStrategy(maxRetries: 10, baseDelay: 1.0,  maxDelay: 64.0,  jitter: true)
    static let mqttAggressive   = RetryStrategy(maxRetries: 20, baseDelay: 0.5,  maxDelay: 32.0,  jitter: true)
    static let mqttConservative = RetryStrategy(maxRetries: 5,  baseDelay: 2.0,  maxDelay: 120.0, jitter: true)
}
