//
//  APIEndpoint.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

// Contrat de base d'un endpoint HTTP.
// Types purs Foundation — zéro dépendance sur URLSession ou NetworkKit.
//
// EndpointPolicyProviding (CircuitBreaker, RateLimit, Cache...) vit dans NetworkKit
// car il référence des types de policy réseau définis dans NetworkKit/Policy/.

import Foundation

// MARK: - HTTPMethod

public enum HTTPMethod: String, Sendable {
    case get    = "GET"
    case post   = "POST"
    case put    = "PUT"
    case delete = "DELETE"
    case patch  = "PATCH"
}

// MARK: - APIEndpoint

/// Contrat minimal d'un endpoint HTTP.
///
/// Chaque feature définit ses endpoints en conformant ce protocole.
/// Les policies réseau (retry, cache, circuit breaker...) sont ajoutées
/// via `EndpointPolicyProviding` dans NetworkKit.
///
/// ```swift
/// enum AuthEndpoint: APIEndpoint {
///     case login(credentials: LoginRequest)
///
///     var path: String {
///         switch self { case .login: return "/auth/login" }
///     }
///     var method: HTTPMethod { .post }
///     var parameters: [String: Any]? { nil }
///     var headers: [String: String]? { nil }
/// }
/// ```
public protocol APIEndpoint: Sendable {
    nonisolated var path: String { get }
    nonisolated var method: HTTPMethod { get }
    nonisolated var parameters: [String: Any]? { get }
    nonisolated var headers: [String: String]? { get }
}
