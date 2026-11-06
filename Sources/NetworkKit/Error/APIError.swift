// MARK: - NetworkKit/Error/APIError.swift

import Foundation

public enum APIError: Error, LocalizedError, Sendable {

    // MARK: - Réseau
    case invalidURL
    case invalidResponse
    case noInternetConnection
    case networkConnectionLost
    case timeout
    case networkError(Error)
    case sslError(Error)

    // MARK: - Auth
    case unauthorized
    case forbidden

    // MARK: - Client
    case notFound
    case badRequest(message: String?)
    case clientError(statusCode: Int, message: String?)
    case emptyResponse

    // MARK: - Serveur
    case serverError(statusCode: Int)

    // MARK: - Limitation
    case rateLimited(endpointKey: String)
    case circuitBreakerOpen(endpointKey: String)

    // MARK: - Données
    case decodingError(Error)

    // MARK: - Contrôle de flux
    case cancelled
    case unknown(String)
    case custom(String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .invalidURL:                       return "URL invalide"
        case .invalidResponse:                  return "Réponse invalide du serveur"
        case .noInternetConnection:             return "Pas de connexion Internet"
        case .networkConnectionLost:            return "Connexion réseau perdue"
        case .timeout:                          return "Timeout de la requête"
        case .networkError(let e):              return "Erreur réseau : \(e.localizedDescription)"
        case .sslError(let e):                  return "Erreur SSL : \(e.localizedDescription)"
        case .unauthorized:                     return "Non autorisé — veuillez vous reconnecter"
        case .forbidden:                        return "Accès refusé"
        case .notFound:                         return "Ressource non trouvée"
        case .badRequest(let msg):              return msg ?? "Requête invalide"
        case .clientError(let code, let msg):   return msg ?? "Erreur client (\(code))"
        case .emptyResponse:                    return "Réponse vide du serveur"
        case .serverError(let code):            return "Erreur serveur (\(code))"
        case .rateLimited(let key):             return "Trop de requêtes pour \(key)"
        case .circuitBreakerOpen(let key):      return "Service indisponible : \(key)"
        case .decodingError(let e):             return "Erreur de décodage : \(e.localizedDescription)"
        case .cancelled:                        return "Requête annulée"
        case .unknown(let msg):                 return msg
        case .custom(let msg):                  return msg
        }
    }

    // MARK: - Helpers

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    public var isNetworkRelated: Bool {
        switch self {
        case .timeout, .noInternetConnection, .networkConnectionLost, .networkError:
            return true
        default:
            return false
        }
    }

    public var shouldTriggerCircuitBreaker: Bool {
        switch self {
        case .noInternetConnection, .networkConnectionLost, .timeout, .networkError:
            return true
        case .serverError(let code):
            return code >= 500
        default:
            return false
        }
    }
}
