// MARK: - NetworkKit/Policy/EndpointsPolicies.swift

import Foundation

// MARK: - EndpointCachePolicy
public enum EndpointCachePolicy: Sendable {
    case noCache //Ignore le cache, va toujours au réseau
    case networkFirst(ttl: TimeInterval) //Va d’abord au réseau, si échec utilise le cache
    case cacheOnly //Utilise uniquement le cache, échoue si cache vide
    case alwaysUseCache(ttl: TimeInterval) //Utilise le cache si dispo, sinon va au réseau
    
    var ttl: TimeInterval {
        switch self {
        case .networkFirst(let ttl), .alwaysUseCache(let ttl):
            return ttl
        case .cacheOnly, .noCache:
            return 0
        }
    }
}

// MARK: - EndpointRetryPolicy

public struct EndpointRetryPolicy: Sendable {
    public let maxRetries: Int
    public let retryOn: Set<RetryTrigger>

    public init(maxRetries: Int, retryOn: Set<RetryTrigger>) {
        self.maxRetries = maxRetries
        self.retryOn = retryOn
    }

    /// Retry standard — timeout, réseau, 5xx.
    public static let standard = EndpointRetryPolicy(
        maxRetries: 3,
        retryOn: [.timeout, .noInternet, .serverError]
    )

    /// Retry agressif — auth, refresh token, critical flows.
    public static let aggressive = EndpointRetryPolicy(
        maxRetries: 5,
        retryOn: [.timeout, .noInternet, .serverError, .rateLimited]
    )

    /// Retry minimal — background, low priority.
    public static let light = EndpointRetryPolicy(
        maxRetries: 1,
        retryOn: [.timeout]
    )
}

// MARK: - RetryTrigger

public enum RetryTrigger: Hashable, Sendable {
    case timeout
    case noInternet
    case serverError
    case rateLimited
}
