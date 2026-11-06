//
//  DevelopmentPINVerifier.swift
//  FeatureChat
//
//  **Debug seulement** — accepte tout PIN en attendant la route serveur.
//

#if DEBUG
import Foundation
import WaanguCoreKit

/// Accepte **n'importe quel** PIN, pour tester Copilot sans Face ID.
///
/// Provisoire : aucune route ne vérifie encore le PIN (question 5 de
/// `BACKEND_MISSING_FINANCE_CONTRACTS.md`). Absent des builds Release, où
/// `UnavailableStepUpPINVerifier` refuse tout PIN. À retirer dès que la route
/// existe — et à remplacer par l'implémentation qui l'appelle.
struct DevelopmentPINVerifier: StepUpPINVerifying {
    func verify(pin: String, correlationID: CorrelationId,
                deviceID: String) async -> Result<StepUpAttestation, FinanceError> {
        print("[FinanceStepUp] DEBUG: PIN accepted without server check — temporary")
        return .success(StepUpAttestation(level: .pin, correlationID: correlationID, deviceID: deviceID))
    }
}
#endif
