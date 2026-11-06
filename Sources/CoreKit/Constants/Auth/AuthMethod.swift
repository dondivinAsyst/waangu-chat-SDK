//
//  AuthMethod.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Méthode d'authentification requise par le backend pour une opération.
public enum AuthMethod: String, Sendable, Codable, CaseIterable {
    case pin    = "PIN"
    case otp    = "OTP"
    case twoFA  = "2FA"
    case no2FA  = "NO2FA"
    case none   = "NONE"

    public var requiresUserInput: Bool {
        switch self {
        case .pin, .otp, .twoFA: return true
        case .no2FA, .none:      return false
        }
    }
}

/// Identifiant du type de client émetteur dans les transactions.
public enum SenderClient: String, Sendable {
    case customer = "customer"
}

public enum Currency: String, Sendable {
    case currencyCode = "BIF"
}
