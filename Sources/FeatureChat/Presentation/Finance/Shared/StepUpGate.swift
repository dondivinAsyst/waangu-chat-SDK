//
//  StepUpGate.swift
//  FeatureChat
//
//  Authentification renforcée avant une opération sensible — Bloc 3 §52.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Satisfait le niveau de step-up **exigé par le backend**, et rend l'attestation.
///
/// **Le client ne décide pas du risque.** Il reçoit un niveau et applique le
/// mécanisme correspondant. Choisir localement quand demander Face ID
/// reviendrait à évaluer le risque d'une opération sans en connaître ni le
/// montant cumulé, ni l'historique, ni la juridiction.
struct StepUpGate: View {

    let authenticator: any StepUpAuthenticating
    let requiredLevel: StepUpLevel
    let reason: String
    let correlationID: CorrelationId
    let deviceID: String
    let onSatisfied: (StepUpAttestation) -> Void
    let onCancel: () -> Void

    @State private var phase: Phase = .idle

    private enum Phase: Equatable {
        case idle
        case authenticating
        case unavailable(String)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: iconName)
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text(FinanceStrings.stepUpTitle)
                .font(.headline)

            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            switch phase {
            case .authenticating:
                ProgressView()
            case .unavailable(let m), .failed(let m):
                Text(m)
                    .font(.caption)
                    .foregroundStyle(AppColors.statusWarning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            case .idle:
                EmptyView()
            }

            Button {
                Task { await authenticate() }
            } label: {
                Text(FinanceStrings.stepUpAuthenticate).frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .disabled(phase == .authenticating)

            Button(FinanceStrings.cancel) { onCancel() }
                .font(.subheadline)
                .disabled(phase == .authenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .preference(key: FinanceActivityBusyKey.self, value: phase == .authenticating)
        .navigationBarBackButtonHidden(phase == .authenticating)
        .interactiveDismissDisabled(phase == .authenticating)
    }

    private var iconName: String {
        switch requiredLevel {
        case .none, .pin:                return "lock"
        case .biometric:                 return "faceid"
        case .biometricAndOTP, .fullReauth: return "lock.shield"
        }
    }

    private func authenticate() async {
        guard phase != .authenticating else { return }
        phase = .authenticating

        do {
            let attestation = try await authenticator.satisfyStepUp(
                level: requiredLevel,
                reason: reason,
                correlationID: correlationID,
                deviceID: deviceID
            )

            // **Le niveau atteint peut être inférieur au niveau demandé** — le
            // système propose parfois un repli. On le laisse passer au backend,
            // qui reste seul juge : refuser ici masquerait l'information que le
            // backend a besoin de pondérer.
            onSatisfied(attestation)

        } catch StepUpError.userCancelled {
            // Une annulation n'est pas un incident. Retour à l'état neutre.
            phase = .idle
        } catch StepUpError.lockedOut {
            phase = .failed(FinanceStrings.stepUpLockedOut)
        } catch StepUpError.levelUnavailable {
            phase = .unavailable(FinanceStrings.stepUpLevelUnavailable)
        } catch {
            phase = .failed(FinanceStrings.stepUpFailed)
        }
    }
}
