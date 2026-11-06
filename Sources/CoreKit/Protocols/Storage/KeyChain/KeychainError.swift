//
//  KeychainError.swift
//  AppModules
//
//  Created by Asyst on 3/24/26ddddddddddddddddd.
//

import Foundation

public enum KeychainError: Error, LocalizedError, Sendable {
    /// L'opération Security a échoué avec un code OSStatus.
    case securityError(status: OSStatus)
    /// Les données ne peuvent pas être converties en UTF-8.
    case encodingFailed

    /// Les données Keychain ne peuvent pas être décodées vers le type demandé.
    case decodingFailed(type: String)

    public var errorDescription: String? {
        switch self {
        case .securityError(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error: \(message) (\(status))"
            }
            return "Keychain error: OSStatus \(status)"
        case .encodingFailed:
            return "Failed to encode value to UTF-8 data"
        case .decodingFailed(let type):
            return "Failed to decode Keychain data to \(type)"
        }
    }
}
