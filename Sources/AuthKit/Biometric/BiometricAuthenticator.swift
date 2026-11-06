//
//  BiometricAuthenticator.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation
import LocalAuthentication

/// Implémentation de `BiometricAuthenticatorProtocol` via `LAContext`.
///
/// Chaque appel crée un nouveau `LAContext` — un context ne doit pas
/// être réutilisé après évaluation (état interne pollué).
public final class BiometricAuthenticator: BiometricAuthenticatorProtocol, @unchecked Sendable {

    public init() {}

    public func biometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType.toBiometricType()
    }

    public func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    public func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let laError = error as? LAError {
                throw laError.toBiometricError()
            }
            throw BiometricError.unknown
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch let laError as LAError {
            throw laError.toBiometricError()
        } catch {
            throw BiometricError.unknown
        }
    }
}
