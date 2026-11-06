//
//  BiometricError.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation
import LocalAuthentication

public enum BiometricError: Error, LocalizedError, Sendable {

    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockedOut
    case authenticationFailed
    case userCancel
    case systemCancel
    case passcodeNotSet
    case unknown

    public var errorDescription: String? {
        switch self {
        case .biometryNotAvailable:
            return "L'authentification biométrique n'est pas disponible sur cet appareil."
        case .biometryNotEnrolled:
            return "Aucune donnée biométrique n'est enregistrée sur cet appareil."
        case .biometryLockedOut:
            return "L'authentification biométrique est verrouillée. Utilisez votre code pour déverrouiller."
        case .authenticationFailed:
            return "L'authentification a échoué. Veuillez réessayer."
        case .userCancel:
            return "Authentification annulée par l'utilisateur."
        case .systemCancel:
            return "L'authentification a été annulée par le système."
        case .passcodeNotSet:
            return "Aucun code d'accès n'est défini sur cet appareil."
        case .unknown:
            return "Erreur inconnue lors de l'authentification biométrique."
        }
    }

    public var alertTitle: String {
        switch self {
        case .biometryLockedOut:     return "Biométrie verrouillée"
        case .authenticationFailed:  return "Échec d'authentification"
        case .biometryNotEnrolled:   return "Aucune donnée biométrique"
        default:                     return "Erreur biométrique"
        }
    }
}

// MARK: - LAError → BiometricError

extension LAError {
    func toBiometricError() -> BiometricError {
        switch self.code {
        case .biometryNotAvailable:  return .biometryNotAvailable
        case .biometryNotEnrolled:   return .biometryNotEnrolled
        case .biometryLockout:       return .biometryLockedOut
        case .authenticationFailed:  return .authenticationFailed
        case .userCancel:            return .userCancel
        case .systemCancel:          return .systemCancel
        case .passcodeNotSet:        return .passcodeNotSet
        default:                     return .unknown
        }
    }
}
