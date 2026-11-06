//
//  BiometricType.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import LocalAuthentication

public enum BiometricType: String, Sendable {
    case none
    case touchID
    case faceID
    case opticID
    case unknown
}

extension LABiometryType {
    func toBiometricType() -> BiometricType {
        switch self {
        case .none:              return .none
        case .touchID:           return .touchID
        case .faceID:            return .faceID
        case .opticID:           return .opticID
        @unknown default:        return .unknown
        }
    }
}
