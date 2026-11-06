// MARK: - NetworkKit/Middlewares/HTTPMiddlewareProtocol.swift

import Foundation

// MARK: - HTTPMiddlewareProtocol

/// Contrat de middleware HTTP.
///
/// Pipeline dans APIClient :
///   prepare()          → FIFO avant envoi (auth, logging, headers)
///   process(response:) → LIFO après réception (cache store, décompression)
///   process(error:)    → FIFO sur erreur (auth refresh, cache fallback)
public protocol HTTPMiddlewareProtocol: Sendable {

    func prepare(
        _ request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> URLRequest

    func process(
        response data: Data,
        for request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> Data

    func process(
        error: APIError,
        for request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> Data?
}

// MARK: - Default implementations (pass-through)
//
public extension HTTPMiddlewareProtocol {

    func prepare(
        _ request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> URLRequest {
        request
    }

    func process(
        response data: Data,
        for request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> Data {
        data
    }

    func process(
        error: APIError,
        for request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> Data? {
        nil
    }
}

// MARK: - RetryCapable

/// Protocole séparé pour les capacités de retry.
/// Seul `RetryMiddleware` y conforme — les autres middlewares ne sont pas concernés.
///
/// Séparé de `HTTPMiddlewareProtocol` pour éviter de forcer tous les middlewares
/// à implémenter des méthodes qui ne les concernent pas.
public protocol RetryCapable: Sendable {
    var maxRetries: Int { get async }
    /// - Parameter isIdempotent: whether repeating the request is safe. A request
    ///   that is not idempotent may only be repeated when it provably never
    ///   reached the server — see `EndpointPolicyProviding.isIdempotent`.
    func shouldRetry(error: APIError, attempt: Int, isIdempotent: Bool) async -> Bool
    func retryDelay(for attempt: Int) async -> TimeInterval
    func logRetry(endpointKey: String, attempt: Int, delay: TimeInterval, error: APIError) async
}
