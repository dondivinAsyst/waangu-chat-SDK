// MARK: - NetworkKit/Error/APIErrorMapper.swift
//
// Implémentation concrète de ErrorMapperProtocol (CoreKit).
// Mappe APIError (NetworkKit) → AppError (CoreKit).

import Foundation
import WaanguCoreKit

public struct APIErrorMapper: ErrorMapperProtocol {

    public init() {}

    /// Mappe n'importe quelle Error vers AppError.
    /// Cast interne vers APIError — si l'erreur n'est pas une APIError,
    /// retourne `.unknown`.
    public func map(_ error: Error) -> AppError {
        guard let apiError = error as? APIError else {
            return .unknown(error.localizedDescription)
        }
        return mapAPIError(apiError)
    }

    // MARK: - Mapping APIError → AppError

    private func mapAPIError(_ error: APIError) -> AppError {
        switch error {

        // Réseau
        case .invalidURL:           return .networkError("URL invalide")
        case .invalidResponse:      return .networkError("Réponse serveur invalide")
        case .noInternetConnection: return .noInternetConnection
        case .networkConnectionLost: return .networkError("Connexion réseau perdue")
        case .timeout:              return .timeout
        case .networkError(let e):  return .networkError(e.localizedDescription)
        case .sslError(let e):      return .networkError("Erreur SSL : \(e.localizedDescription)")

        // Auth
        case .unauthorized:         return .authenticationError("Non autorisé")
        case .forbidden:            return .forbidden

        // Client
        case .notFound:             return .notFound
        case .badRequest(let msg):  return .badRequest(message: msg ?? "Requête invalide")
        case .clientError(let code, let msg):
            return .validationError(statusCode: code, message: msg ?? "Erreur client (\(code))")
        case .emptyResponse:        return .emptyResponse

        // Serveur
        case .serverError:          return .serverError

        // Limitation
        case .rateLimited:          return .rateLimited
        case .circuitBreakerOpen:   return .serviceUnavailable

        // Données
        case .decodingError(let e): return .decodingError(e.localizedDescription)

        // Contrôle de flux
        case .cancelled:            return .cancelled
        case .unknown(let msg):     return .unknown(msg)
        case .custom(let msg):      return .unknown(msg)
        }
    }
}
