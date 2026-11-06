//
//  ProximityPaymentView.swift
//  FeatureChat
//
//  Paiement sans contact — Bloc 6, chapitre 47.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Payer en approchant le téléphone d'un terminal.
///
/// L'écran ne lit pas le NFC lui-même : le terminal est présenté par la couche
/// matérielle, et tout ce qui compte ici est **ce que la session a épinglé**.
/// Le montant, le marchand et le terminal sont figés à l'ouverture ; l'écran
/// revérifie avant de confirmer et refuse tout écart.
struct ProximityPaymentView: View {

    let sessions: any ProximityPaymentSessioning
    /// Le terminal tel que la couche matérielle l'a lu.
    let presentedTerminal: TerminalIdentitySnapshot
    let attestation: DeviceAttestationResult
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .checkingCapability
    /// Session dont le paiement est d'issue inconnue.
    @State private var uncertainSessionID: String?
    @State private var now = Date()
    @State private var isClosing = false
    @Environment(\.dismiss) private var pop
    @State private var idempotency: IdempotencyContext?

    /// Bat à la seconde : sans cela, l'expiration de la session ne se verrait
    /// qu'au prochain geste, et l'écran proposerait de payer sur une session
    /// déjà morte.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private enum Phase {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case checkingCapability
        case unavailable(ProximityUnavailableReason?)
        case opening
        case ready(ProximityPaymentSession)
        case awaitingStepUp(ProximityPaymentSession)
        case confirming
        /// Le terminal présenté ne correspond plus à celui épinglé.
        case mismatch(ProximityMismatch)
        case outcome(ProximityPaymentOutcome)
        case failed(String)
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .checkingCapability:
                    FinanceProgress(label: FinanceStrings.nfcChecking)
                case .unavailable(let reason):
                    unavailable(reason)
                case .opening:
                    FinanceProgress(label: FinanceStrings.nfcOpening)
                case .ready(let session):
                    ready(session)
                case .awaitingStepUp(let session):
                    gate(session)
                case .confirming:
                    FinanceProgress(label: FinanceStrings.nfcConfirming)
                case .mismatch(let mismatch):
                    mismatchView(mismatch)
                case .outcome(let outcome):
                    outcomeView(outcome)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: uncertainSessionID.map { id in { Task { await requery(sessionID: id) } } },
                                                onDismiss: onDismiss)
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.nfcTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: isWorking,
                                 back: { Task { await dismiss(returningToParent: true) } },
                                 onClose: { Task { await dismiss() } })
        }
        .financeLoadOnce { await start() }
        .onReceive(tick) { now = $0 }
    }

    private var isWorking: Bool {
        if isClosing { return true }
        switch phase {
        case .checkingCapability, .opening, .confirming: return true
        default: return false
        }
    }

    // MARK: - Cycle de vie

    private func start() async {
        phase = .checkingCapability
        switch await sessions.capability() {
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        case .success(let capability):
            guard capability.isAvailable else {
                phase = .unavailable(capability.unavailableReason)
                return
            }
            await open()
        }
    }

    private func open() async {
        // Une attestation vieillie ne vaut rien : l'appareil a pu changer
        // d'état depuis sa capture. On refuse plutôt que d'ouvrir une session
        // sur une preuve périmée.
        guard attestation.isFresh() else {
            phase = .unavailable(.deviceNotAttested)
            return
        }

        phase = .opening
        idempotency = idempotency ?? IdempotencyContext.new(deviceID: deviceID)
        guard let idempotency else { return }

        let result = await sessions.open(
            terminal: presentedTerminal, attestation: attestation, idempotency: idempotency
        )
        switch result {
        case .success(let session): phase = .ready(session)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Revérifie le terminal, puis confirme.
    ///
    /// La vérification a lieu **au moment du geste**, pas à l'ouverture : c'est
    /// entre les deux qu'un terminal substitué ou un montant modifié
    /// apparaîtraient.
    private func requestConfirmation(_ session: ProximityPaymentSession) {
        if let mismatch = session.validate(presented: presentedTerminal) {
            phase = .mismatch(mismatch)
            return
        }
        guard session.isConfirmable(at: Date()) else {
            phase = .failed(FinanceStrings.nfcSessionExpired)
            return
        }
        phase = .awaitingStepUp(session)
    }

    private func confirm(_ session: ProximityPaymentSession,
                         attestation stepUpAttestation: StepUpAttestation?) async {
        guard case .awaitingStepUp = phase else { return }
        guard let idempotency else { phase = .failed(FinanceStrings.sendOperationLost); return }
        phase = .confirming

        let result = await sessions.confirm(
            session: session, idempotency: idempotency, stepUp: stepUpAttestation
        )
        switch result {
        case .success(let outcome): phase = .outcome(outcome)
        case .failure(let error) where FinancialOutcomeRoute.isFinalityUnknown(error):
            // Le terminal a peut-être encaissé. On redemande l'état de la session ;
            // on ne représente jamais le paiement.
            uncertainSessionID = session.id
            phase = .uncertain(nil)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Redemande l'état. **Ne relance jamais le paiement.**
    private func requery(_ outcome: ProximityPaymentOutcome) async {
        await requery(sessionID: outcome.sessionID)
    }

    private func requery(sessionID: String) async {
        switch await sessions.requery(sessionID: sessionID) {
        case .success(let fresh): phase = .outcome(fresh)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func dismiss(returningToParent: Bool = false) async {
        guard !isWorking else { return }
        isClosing = true
        // Leaving an unsent review/authentication page releases its existing session.
        if let idempotency {
            switch phase {
            case .ready(let session), .awaitingStepUp(let session):
                _ = await sessions.cancel(sessionID: session.id, idempotency: idempotency)
            default: break
            }
        }
        if returningToParent { pop() } else { onDismiss() }
    }

    // MARK: - Vues

    private func unavailable(_ reason: ProximityUnavailableReason?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wave.3.right.circle")
                .font(.system(size: 44)).foregroundStyle(.tertiary)
            Text(FinanceStrings.nfcUnavailableTitle).font(.subheadline.weight(.medium))
            // Chaque motif appelle un geste différent : activer le NFC n'est
            // pas la même réponse qu'un pays non ouvert.
            Text(FinanceStrings.nfcUnavailableReason(reason))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func ready(_ session: ProximityPaymentSession) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 50)).foregroundStyle(.tint)

            // Le nom du marchand en grand : payer un nom qu'on ne reconnaît
            // pas doit pouvoir s'interrompre avant le geste.
            Text(session.terminal.merchantDisplayName)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(AmountEntry.format(session.terminal.amount.majorUnitsForDisplay, session.terminal.amount.currency.code))
                .font(.largeTitle.weight(.bold)).monospacedDigit()

            // Le compte à rebours : une session de proximité vit le temps d'un
            // geste, et l'utilisateur doit le savoir avant qu'elle expire.
            Label(remaining(session), systemImage: "clock")
                .font(.caption).foregroundStyle(session.hasExpired(at: now) ? AppColors.statusWarning : .secondary)
                .monospacedDigit()

            if session.relayRisk.forcesStepUp {
                Label(FinanceStrings.nfcRelayElevated, systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(AppColors.statusWarning)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }

            Spacer()

            Button { requestConfirmation(session) } label: {
                Text(FinanceStrings.nfcConfirm).frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.isConfirmable(at: now))

            if !session.relayRisk.permitsPayment {
                Text(FinanceStrings.nfcRelayBlocked)
                    .font(.caption).foregroundStyle(AppColors.statusWarning)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Le terminal ne correspond plus. **Aucun paiement ne suit.**
    private func mismatchView(_ mismatch: ProximityMismatch) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 44)).foregroundStyle(AppColors.statusDanger)
            Text(FinanceStrings.nfcMismatchTitle).font(.headline)
            Text(FinanceStrings.nfcMismatchReason(mismatch))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }
        .padding(.top, 48)
        .accessibilityElement(children: .combine)
    }

    /// L'issue, **sans jamais confondre incertain et échoué**.
    ///
    /// C'est ce qui produit les doubles débits : l'utilisateur voit « échec »,
    /// réessaie, et paie deux fois une opération qui avait abouti.
    private func outcomeView(_ outcome: ProximityPaymentOutcome) -> some View {
        VStack(spacing: 14) {
            Image(systemName: outcomeIcon(outcome.truth))
                .font(.system(size: 44))
                .foregroundStyle(outcomeTint(outcome.truth))

            Text(FinanceStrings.nfcTruthLabel(outcome.truth)).font(.headline)
            Text(FinanceStrings.nfcTruthDetail(outcome.truth))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)

            if let reference = outcome.reference {
                Text(reference.id)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            // Requêter, jamais rejouer. Le bouton dit « actualiser », pas
            // « réessayer » : ce sont deux gestes opposés.
            if outcome.truth.requiresRequery {
                Button(FinanceStrings.nfcRefreshStatus) { Task { await requery(outcome) } }
                    .buttonStyle(.borderedProminent)
            }

            // Une nouvelle tentative n'est proposée que si rien n'a abouti et
            // rien n'est en vol.
            if outcome.truth.permitsRetry {
                Button(FinanceStrings.nfcRetry) { Task { await start() } }
                    .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(.top, 40)
        .accessibilityElement(children: .combine)
    }

    private func gate(_ session: ProximityPaymentSession) -> some View {
        StepUpGate(
            authenticator: stepUp,
            // Un risque de relais élevé force l'authentification même sous le
            // plafond sans contact : c'est le seul moyen de distinguer le
            // porteur d'un relais.
            requiredLevel: .biometric,
            reason: FinanceStrings.stepUpReasonProximity,
            correlationID: idempotency?.correlationID ?? CorrelationId(),
            deviceID: deviceID,
            onSatisfied: { attestation in
                Task { await confirm(session, attestation: attestation) }
            },
            onCancel: { phase = .ready(session) }
        )
    }

    private func remaining(_ session: ProximityPaymentSession) -> String {
        let seconds = max(0, Int(session.expiresAt.timeIntervalSince(now)))
        return seconds > 0
            ? String(format: FinanceStrings.nfcExpiresIn, seconds)
            : FinanceStrings.nfcSessionExpired
    }

    private func outcomeIcon(_ truth: ProximityPaymentTruth) -> String {
        switch truth {
        case .confirmed:              return "checkmark.seal.fill"
        case .processing, .pending:   return "clock"
        case .unknown:                return "questionmark.circle"
        case .failed:                 return "xmark.octagon"
        case .reversed:               return "arrow.uturn.backward.circle"
        }
    }

    private func outcomeTint(_ truth: ProximityPaymentTruth) -> Color {
        switch truth {
        case .confirmed:                        return AppColors.statusSuccess
        case .processing, .pending, .unknown:   return AppColors.statusWarning
        case .failed, .reversed:                return .secondary
        }
    }
}
