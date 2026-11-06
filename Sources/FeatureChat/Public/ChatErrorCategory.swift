//
//  ChatErrorCategory.swift
//  FeatureChat
//
//  Plan SDK, étape 1.11 — catégories d'erreur de la spécification (§16.1).
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

/// Ce que l'hôte peut faire d'une erreur du Chat, sans en connaître le type.
///
/// Les onze catégories de la spécification (§16.1), lues depuis les erreurs qui
/// existent déjà : `AppError` (CoreKit), `APIError` (NetworkKit) et `URLError`.
/// Une erreur inconnue vaut `.unknown` — jamais une catégorie devinée.
public enum ChatErrorCategory: String, Sendable, CaseIterable {
    case networkUnavailable
    case sessionExpired
    case authenticationRequired
    case permissionDenied
    case resourceNotFound
    case validationFailed
    case rateLimited
    case serviceUnavailable
    case conflict
    case timeout
    case unknown

    public init(_ error: Error) {
        switch error {
        case let error as AppError:   self = Self.category(of: error)
        case let error as APIError:   self = Self.category(of: error)
        case let error as URLError:   self = Self.category(of: error)
        default:                      self = .unknown
        }
    }

    private static func category(of error: AppError) -> ChatErrorCategory {
        switch error {
        case .networkError, .noInternetConnection:      return .networkUnavailable
        case .timeout:                                   return .timeout
        case .serverError, .serviceUnavailable:          return .serviceUnavailable
        case .rateLimited:                               return .rateLimited
        case .notFound:                                  return .resourceNotFound
        case .forbidden:                                 return .permissionDenied
        case .validationError(let statusCode, _):        return statusCode == 409 ? .conflict : .validationFailed
        case .badRequest:                                return .validationFailed
        case .authenticationError, .biometric:           return .authenticationRequired
        case .sessionExpired, .tokenRefreshFailed:       return .sessionExpired
        case .decodingError, .emptyResponse,
             .cancelled, .unknown:                       return .unknown
        }
    }

    private static func category(of error: APIError) -> ChatErrorCategory {
        switch error {
        case .noInternetConnection, .networkConnectionLost,
             .networkError, .sslError:                   return .networkUnavailable
        case .timeout:                                   return .timeout
        case .unauthorized:                              return .authenticationRequired
        case .forbidden:                                 return .permissionDenied
        case .notFound:                                  return .resourceNotFound
        case .badRequest:                                return .validationFailed
        case .clientError(let statusCode, _):            return statusCode == 409 ? .conflict : .validationFailed
        case .serverError, .circuitBreakerOpen:          return .serviceUnavailable
        case .rateLimited:                               return .rateLimited
        case .invalidURL, .invalidResponse, .emptyResponse,
             .decodingError, .cancelled, .unknown, .custom: return .unknown
        }
    }

    private static func category(of error: URLError) -> ChatErrorCategory {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost,
             .cannotConnectToHost, .cannotFindHost,
             .dataNotAllowed, .internationalRoamingOff:  return .networkUnavailable
        case .timedOut:                                  return .timeout
        case .userAuthenticationRequired:                return .authenticationRequired
        default:                                         return .unknown
        }
    }
}
