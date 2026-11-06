//
//  AppError.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

// Erreurs domaine unifiées.
// Zéro dépendance sur AuthKit, NetworkKit ou tout autre module.
//
// Note sur le cas biometric :
// BiometricError est défini dans AuthKit.
// Pour éviter une dépendance CoreKit → AuthKit, on encapsule
// le message d'erreur biométrique en String plutôt qu'en type concret.
// AuthKit mappe BiometricError → AppError.biometric(String) avant de throw.

import Foundation

/// Erreurs domaine unifiées de l'application.
///
/// Frontière entre erreurs techniques (APIError, CoreData errors...)
/// et couche présentation. Les repositories mappent vers ce type.
///
/// Règle : la présentation ne connaît que `AppError`.
public enum AppError: Error, LocalizedError, Equatable, Sendable {

    // MARK: - Réseau
    case networkError(String)
    case noInternetConnection
    case timeout

    // MARK: - Serveur
    case serverError
    case rateLimited
    case serviceUnavailable

    // MARK: - Client
    case notFound
    case forbidden
    case validationError(statusCode: Int, message: String)
    case badRequest(message: String)

    // MARK: - Auth
    case authenticationError(String)
    case sessionExpired
    case tokenRefreshFailed

    // MARK: - Données
    case decodingError(String)
    case emptyResponse

    // MARK: - Hardware / Système
    /// Message d'erreur biométrique encapsulé en String
    /// pour éviter une dépendance CoreKit → AuthKit.
    case biometric(String)
    case cancelled

    // MARK: - Générique
    case unknown(String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .networkError(let msg):            return msg
        case .noInternetConnection:             return "Pas de connexion internet"
        case .timeout:                          return "La requête a expiré"
        case .serverError:                      return "Erreur serveur"
        case .rateLimited:                      return "Trop de requêtes, réessayez dans un moment"
        case .serviceUnavailable:               return "Service temporairement indisponible"
        case .notFound:                         return "Ressource non trouvée"
        case .forbidden:                        return "Accès refusé"
        case .validationError(_, let msg):      return msg
        case .badRequest(let msg):              return msg
        case .authenticationError(let msg):     return msg
        case .sessionExpired:                   return "Session expirée, veuillez vous reconnecter"
        case .tokenRefreshFailed:               return "Impossible de renouveler la session"
        case .decodingError(let msg):           return msg
        case .emptyResponse:                    return "Réponse vide du serveur"
        case .biometric(let msg):               return msg
        case .cancelled:                        return "Opération annulée"
        case .unknown(let msg):                 return msg
        }
    }

    // MARK: - Helpers

    /// `true` si l'erreur est liée à l'auth — l'UI peut rediriger vers login.
    public var isAuthError: Bool {
        switch self {
        case .authenticationError, .sessionExpired, .tokenRefreshFailed: return true
        default: return false
        }
    }

    /// `true` si l'erreur est transitoire et que l'utilisateur peut réessayer.
    public var isRetryable: Bool {
        switch self {
        case .networkError, .noInternetConnection, .timeout,
             .serverError, .rateLimited, .serviceUnavailable: return true
        default: return false
        }
    }
}
