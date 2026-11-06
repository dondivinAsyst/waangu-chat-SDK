//
//  BiometricAuthenticatorProtocol.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Contrat d'authentification biométrique (Face ID, Touch ID, Optic ID).
///
/// L'implémentation concrète (`BiometricAuthenticator`) utilise `LAContext`.
/// En test, injecter un mock qui retourne des résultats déterministes.
public protocol BiometricAuthenticatorProtocol: Sendable {

    /// Type de biométrie disponible sur l'appareil.
    func biometricType() -> BiometricType

    /// `true` si le hardware et l'enrôlement sont OK.
    func isBiometricAvailable() -> Bool

    /// Lance l'authentification biométrique.
    /// - Parameter reason: Message affiché dans le dialogue système.
    /// - Returns: `true` si l'utilisateur s'est authentifié avec succès.
    /// - Throws: `BiometricError` en cas d'échec.
    func authenticate(reason: String) async throws -> Bool
}
