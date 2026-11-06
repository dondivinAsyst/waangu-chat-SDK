// MARK: - NetworkKit/Policy/HTTPRetryPolicy.swift

import Foundation

/// Politique de retry HTTP combinant stratégie + codes retryables.
/// Utilisée par `RetryMiddleware`.
public struct HTTPRetryPolicy: Sendable {

    public let strategy: RetryStrategy
    public let retryableStatusCodes: Set<Int>
    public let retryableURLErrorCodes: Set<URLError.Code>

    public init(
        strategy: RetryStrategy,
        retryableStatusCodes: Set<Int>,
        retryableURLErrorCodes: Set<URLError.Code>
    ) {
        self.strategy = strategy
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableURLErrorCodes = retryableURLErrorCodes
    }
}

// MARK: - Presets

public extension HTTPRetryPolicy {

    /// Profil par défaut — équilibré pour la majorité des endpoints REST.
    static let `default` = HTTPRetryPolicy(
        strategy: .standard,
        retryableStatusCodes: [408, 429, 500, 502, 503, 504],
        retryableURLErrorCodes: [.timedOut, .networkConnectionLost, .notConnectedToInternet]
    )

    /// Profil production — conservateur, évite les retries sur erreurs client.
    static let production = HTTPRetryPolicy(
        strategy: .conservative,
        retryableStatusCodes: [500, 502, 503, 504],
        retryableURLErrorCodes: [.timedOut, .networkConnectionLost]
    )

    /// Profil staging — agressif pour maximiser la couverture de test.
    static let staging = HTTPRetryPolicy(
        strategy: .aggressive,
        retryableStatusCodes: Set(400..<600).subtracting([401, 403]),
        retryableURLErrorCodes: [
            .timedOut, .networkConnectionLost,
            .notConnectedToInternet, .cannotConnectToHost
        ]
    )

    /// Upload — délais plus longs pour les transferts de fichiers.
    static let upload = HTTPRetryPolicy(
        strategy: RetryStrategy(maxRetries: 3, baseDelay: 2.0, maxDelay: 60.0, jitter: true),
        retryableStatusCodes: [408, 429, 500, 502, 503, 504],
        retryableURLErrorCodes: [.timedOut, .networkConnectionLost]
    )

    /// Download — léger, les téléchargements gèrent leur propre reprise.
    static let download = HTTPRetryPolicy(
        strategy: RetryStrategy(maxRetries: 2, baseDelay: 1.0, maxDelay: 30.0, jitter: true),
        retryableStatusCodes: [500, 502, 503, 504],
        retryableURLErrorCodes: [.networkConnectionLost]
    )
}
