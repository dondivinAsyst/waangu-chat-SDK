//
//  DeviceAttestationVerifying.swift
//  CoreKit
//
//  Bloc 9, §13 — vérification d'attestation et verdict de confiance.
//

import Foundation

/// Pourquoi une attestation est refusée.
public enum AttestationVerificationError: Error, Sendable, Equatable {

    /// Le défi ne correspond pas à celui émis. **Rejeu probable.**
    case challengeMismatch

    /// Charge illisible ou vide.
    case malformed

    /// Apple a refusé l'assertion.
    case rejectedByAttestationService

    case unreachable
}

/// Vérifie une attestation d'appareil et rend une décision de confiance.
///
/// **Autorité serveur** : le §13 interdit que l'appareil décide de sa propre
/// intégrité. Il produit une attestation ; c'est ici qu'elle est jugée.
public protocol DeviceAttestationVerifying: Sendable {

    func verify(
        _ attestation: DeviceAttestation,
        expectedChallenge: String
    ) async -> Result<DeviceTrustDecision, AttestationVerificationError>
}

/// Ne vérifie rien et refuse.
///
/// Refuse plutôt que d'accepter : une attestation que personne ne contrôle ne
/// doit pas valoir confiance par défaut.
public struct UnavailableAttestationVerifier: DeviceAttestationVerifying {
    public init() {}
    public func verify(_ attestation: DeviceAttestation,
                       expectedChallenge: String) async -> Result<DeviceTrustDecision, AttestationVerificationError> {
        .failure(.unreachable)
    }
}
