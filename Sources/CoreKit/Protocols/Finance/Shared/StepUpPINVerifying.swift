//
//  StepUpPINVerifying.swift
//  CoreKit
//
//  Le PIN du portefeuille comme repli de Face ID — vérifié par le serveur.
//

import Foundation

/// Vérifie le PIN du portefeuille pour une opération, et rend l'attestation.
///
/// **Jamais sur l'appareil.** L'app ne connaît pas le PIN : seul le serveur
/// peut dire s'il est juste. Accepter six chiffres localement ne serait qu'une
/// apparence de sécurité.
///
/// **BACKEND CONTRACT REQUIRED** — aucune route ne vérifie aujourd'hui le PIN
/// seul : le portefeuille l'envoie avec sa propre transaction
/// (`verifyTransaction(transRefId:pin:)`), et l'execute de Chat Core n'en
/// prend pas. Voir `BACKEND_MISSING_FINANCE_CONTRACTS.md`.
public protocol StepUpPINVerifying: Sendable {
    func verify(pin: String, correlationID: CorrelationId,
                deviceID: String) async -> Result<StepUpAttestation, FinanceError>
}

/// Le repli tant que le serveur ne vérifie pas le PIN : **tout est refusé**.
public struct UnavailableStepUpPINVerifier: StepUpPINVerifying {
    public init() {}

    public func verify(pin: String, correlationID: CorrelationId,
                       deviceID: String) async -> Result<StepUpAttestation, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
