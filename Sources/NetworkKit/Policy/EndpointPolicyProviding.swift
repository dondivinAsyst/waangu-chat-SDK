// MARK: - NetworkKit/Policy/EndpointPolicyProviding.swift

import Foundation

/// Contrat de policies réseau pour un endpoint.
///
/// Combine avec `APIEndpoint` (CoreKit) pour former la signature complète
/// utilisée par `APIClient.request(endpoint:)` :
/// ```swift
/// func request<T: Decodable>(
///     endpoint: any APIEndpoint & EndpointPolicyProviding
/// ) async throws -> T
/// ```
///
/// Les features conforment leurs endpoints à `APIEndpoint` + `EndpointPolicyProviding`
/// mais n'ont besoin d'importer que CoreKit pour `APIEndpoint` —
/// NetworkKit est transparent pour elles via `APIClientProtocol`.
public protocol EndpointPolicyProviding: Sendable {
    var cachePolicy: EndpointCachePolicy { get }
    var circuitBreakerProfile: CircuitBreakerProfile { get }
    var priority: RequestPriority { get }
    var isIdempotent: Bool { get }
    var timeoutPolicy: EndpointTimeoutPolicy { get }
    var rateLimitPolicy: RateLimitPolicy { get }
}

