//
//  APIClientProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.

//
// Contrat minimal du client HTTP — zéro dépendance sur NetworkKit.
//
// Design :
// - CoreKit : APIClientProtocol avec signature minimale (any APIEndpoint)
// - NetworkKit : PolicyAwareAPIClientProtocol étend APIClientProtocol
//               avec signature riche (APIEndpoint & EndpointPolicyProviding)
// - APIClient (NetworkKit) : conforme aux deux
//
// Pourquoi cette séparation :
//   EndpointPolicyProviding référence CircuitBreakerProfile, RateLimitPolicy
//   etc. — des types NetworkKit. CoreKit ne peut pas les connaître.
//   Les features utilisent APIClientProtocol dans leurs repositories
//   sans avoir besoin d'importer NetworkKit.

import Foundation

// MARK: - APIPerformanceMetrics

/// Métriques de performance exposées par le client HTTP.
public struct APIPerformanceMetrics: Sendable {
    public let totalRequests: Int
    public let successCount: Int
    public let failureCount: Int
    public let averageDuration: Double
    public let rateLimitedCount: Int
    public let circuitBreakerBlockCount: Int

    public init(
        totalRequests: Int,
        successCount: Int,
        failureCount: Int,
        averageDuration: Double,
        rateLimitedCount: Int,
        circuitBreakerBlockCount: Int
    ) {
        self.totalRequests = totalRequests
        self.successCount = successCount
        self.failureCount = failureCount
        self.averageDuration = averageDuration
        self.rateLimitedCount = rateLimitedCount
        self.circuitBreakerBlockCount = circuitBreakerBlockCount
    }
}

// MARK: - APIClientProtocol

/// Contrat minimal du client HTTP.
///
/// Utilisé dans les repositories des features — import CoreKit uniquement.
///
/// ```swift
/// final class AuthRepository {
///     private let apiClient: any APIClientProtocol
///
///     func login(_ request: LoginRequest) async throws -> AuthResponse {
///         try await apiClient.request(endpoint: AuthEndpoint.login(request))
///     }
/// }
/// ```
public protocol APIClientProtocol: AnyObject, Sendable {

    /// `true` si le device est connecté au réseau.
    /// Lu dynamiquement depuis NetworkMonitor — jamais un snapshot figé.
    var isConnected: Bool { get async }

    /// Exécute une requête HTTP et décode la réponse en `T`.
    /// - Throws: `APIError` (NetworkKit) mappé en `AppError` par les repositories
    func request<T: Decodable>(
        endpoint: any APIEndpoint
    ) async throws -> T

    /// Annule toutes les requêtes en vol pour un endpoint donné.
    func cancelRequest(for endpoint: any APIEndpoint) async

    /// Annule toutes les requêtes en vol.
    func cancelAllRequests() async

    /// Snapshot des métriques de performance du client.
    func getPerformanceMetrics() async -> APIPerformanceMetrics
}
