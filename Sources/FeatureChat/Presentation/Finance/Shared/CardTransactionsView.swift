//
//  CardTransactionsView.swift
//  FeatureChat
//
//  Transactions cartes, 3DS et contestations — Bloc 6, chapitre 49.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// L'historique d'une carte.
///
/// Chaque ligne dit **ce que son montant représente** : réservé, débité, ou
/// définitif. Une station-service qui réserve 150 € et capture 40 € produirait
/// sinon un historique qui contredit le relevé bancaire.
struct CardTransactionsView: View {

    let cardID: String
    let transactions: any CardTransactionProviding
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var selected: CardTransaction?

    private enum Phase {
        case loading
        case empty
        case loaded([CardTransaction])
        case failed(String)
    }

    private var flowIsBusy: Bool {
        false
    }

    private var flowIsDirty: Bool {
        false
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading: FinanceProgress(label: FinanceStrings.cardTransactionsLoading)
                case .empty:   FinanceMessage(icon: "list.bullet", text: FinanceStrings.cardTransactionsEmpty)
                case .loaded(let list):
                    List(list) { transaction in
                        Button { selected = transaction } label: { row(transaction) }
                            .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.cardTransactions)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(item: $selected) { transaction in
                CardTransactionDetailView(
                    transaction: transaction, transactions: transactions,
                    stepUp: stepUp, deviceID: deviceID,
                    onDismiss: { selected = nil; Task { await load() } }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await transactions.transactions(cardID: cardID, cursor: nil) {
        case .success(let list):
            phase = list.isEmpty ? .empty : .loaded(list)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func row(_ transaction: CardTransaction) -> some View {
        let displayed = transaction.displayedAmount

        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchantNameKey).font(.subheadline.weight(.medium))
                Text(transaction.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
                CardTransactionStateBadge(state: transaction.state)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(AmountEntry.format(displayed.amount.majorUnitsForDisplay, displayed.amount.currency.code))
                    .font(.subheadline).monospacedDigit()
                // L'autorité du montant, dite à côté du montant. « Réservé »
                // et « débité » ne veulent pas dire la même chose au client.
                Text(authorityLabel(displayed.authority))
                    .font(.caption2)
                    .foregroundStyle(displayed.authority == .authorized ? AppColors.statusWarning : .secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func authorityLabel(_ authority: CardAmountAuthority) -> String {
        switch authority {
        case .authorized: return FinanceStrings.cardAmountAuthorized
        case .captured:   return FinanceStrings.cardAmountCaptured
        case .settled:    return FinanceStrings.cardAmountSettled
        }
    }
}

/// Le détail d'une transaction, et ce qu'on peut en faire.
struct CardTransactionDetailView: View {

    let transaction: CardTransaction
    let transactions: any CardTransactionProviding
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .idle
    @State private var pendingDispute: CardDisputeRequest?
    @State private var showsDisputeForm = false

    private enum Phase {
        case idle
        case working
        case opened(CardDispute)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .working: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        false
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .idle:    detail
                case .working: FinanceProgress(label: FinanceStrings.cardWorking)
                case .opened:  FinanceMessage(icon: "checkmark.circle", text: FinanceStrings.cardDisputeOpened)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.cardTransactionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(isPresented: $showsDisputeForm) {
                CardDisputeFormView(
                    transaction: transaction,
                    onSubmit: { request in
                        showsDisputeForm = false
                        pendingDispute = request
                    },
                    onDismiss: { showsDisputeForm = false }
                )
            }
            .financeDestination(item: $pendingDispute) { request in
                StepUpGate(
                    authenticator: stepUp,
                    requiredLevel: .biometric,
                    reason: FinanceStrings.stepUpReasonCardDispute,
                    correlationID: CorrelationId(),
                    deviceID: deviceID,
                    onSatisfied: { attestation in
                        Task { await submit(request, attestation: attestation) }
                    },
                    onCancel: { pendingDispute = nil }
                )
            }
        }
    }

    private func submit(_ request: CardDisputeRequest, attestation: StepUpAttestation?) async {
        pendingDispute = nil
        phase = .working
        let submissionKey199 = await operationKeys.key(for: FinanceOperationKeys.scope("card.dispute", String(describing: request)), deviceID: deviceID)
        let result = await transactions.openDispute(
            request, idempotency: submissionKey199,
            stepUp: attestation
        )
        switch result {
        case .success(let dispute): phase = .opened(dispute)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private var detail: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(transaction.merchantNameKey).font(.headline)
                    CardTransactionStateBadge(state: transaction.state)
                    Text(transaction.reference.id)
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            // Les trois temps, montrés séparément. C'est l'inverse exact du
            // « success / failed » que le chapitre 49 interdit.
            Section(FinanceStrings.detailSection) {
                LabeledContent(FinanceStrings.cardAmountAuthorized,
                               value: money(transaction.authorizedAmount))
                if let captured = transaction.capturedAmount {
                    LabeledContent(FinanceStrings.cardAmountCaptured, value: money(captured))
                }
                if let settled = transaction.settledAmount {
                    LabeledContent(FinanceStrings.cardAmountSettled, value: money(settled))
                }
                if let refunded = transaction.refundedAmount, refunded.minorUnits > 0 {
                    LabeledContent(FinanceStrings.cardAmountRefunded, value: money(refunded))
                }

                // Une autorisation seule : le dire, pour éviter d'attendre un
                // débit qui n'aura peut-être jamais lieu.
                if transaction.capturedAmount == nil && transaction.state == .authorized {
                    Text(FinanceStrings.cardAuthorizedOnlyNote)
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }

            if let original = transaction.originalAmount,
               let currency = transaction.originalCurrency {
                Section(FinanceStrings.cardOriginalAmount) {
                    Text("\(original) \(currency)").monospacedDigit()
                }
            }

            if let threeDS = transaction.threeDSecure {
                Section(FinanceStrings.cardThreeDS) {
                    LabeledContent(FinanceStrings.cardThreeDSFlow, value: flowLabel(threeDS.flow))
                    LabeledContent(FinanceStrings.cardThreeDSResult, value: resultLabel(threeDS.result))
                    // `attempted` transfère la responsabilité sans prouver
                    // l'identité : le confondre avec `authenticated` laisserait
                    // croire à une authentification qui n'a pas eu lieu.
                    if !threeDS.result.isAuthenticated {
                        Text(FinanceStrings.cardThreeDSNotAuthenticated)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let reason = transaction.declineReasonKey {
                Section(FinanceStrings.cardDeclineReason) {
                    Label(reason, systemImage: "xmark.octagon")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }

            Section {
                if transaction.isDisputable() {
                    Button(FinanceStrings.cardOpenDispute) { showsDisputeForm = true }
                } else {
                    // Une autorisation n'est pas contestable : rien n'a bougé,
                    // et l'annuler relève du marchand, pas du réseau.
                    Text(FinanceStrings.cardNotDisputable)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func money(_ value: Money) -> String {
        AmountEntry.format(value.majorUnitsForDisplay, value.currency.code)
    }

    private func flowLabel(_ flow: ThreeDSecureFlow) -> String {
        switch flow {
        case .frictionless: return FinanceStrings.cardThreeDSFrictionless
        case .challenge:    return FinanceStrings.cardThreeDSChallenge
        case .unknown:      return FinanceStrings.cardThreeDSUnknown
        }
    }

    private func resultLabel(_ result: ThreeDSecureResult) -> String {
        switch result {
        case .authenticated: return FinanceStrings.cardThreeDSAuthenticated
        case .attempted:     return FinanceStrings.cardThreeDSAttempted
        case .failed:        return FinanceStrings.cardThreeDSFailed
        case .rejected:      return FinanceStrings.cardThreeDSRejected
        case .unavailable:   return FinanceStrings.cardThreeDSUnavailable
        case .unknown:       return FinanceStrings.cardThreeDSUnknown
        }
    }
}

/// Compose une contestation.
struct CardDisputeFormView: View {

    let transaction: CardTransaction
    let onSubmit: (CardDisputeRequest) -> Void
    let onDismiss: () -> Void

    @State private var kind: CardDisputeKind = .unrecognized
    @State private var reasonKey = ""
    @State private var comment = ""

    private var request: CardDisputeRequest {
        CardDisputeRequest(
            transactionID: transaction.id, kind: kind,
            reasonKey: reasonKey.trimmingCharacters(in: .whitespacesAndNewlines),
            commentText: comment.isEmpty ? nil : comment
        )
    }

    var body: some View {
        FinanceNavigationScope {
            Form {
                Section(FinanceStrings.cardDisputeKind) {
                    Picker(FinanceStrings.cardDisputeKind, selection: $kind) {
                        ForEach(CardDisputeKind.allCases, id: \.self) { value in
                            Text(kindLabel(value)).tag(value)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    // Une opération non reconnue n'est pas un désaccord
                    // commercial : le dire oriente le traitement dès le départ.
                    if kind == .unrecognized {
                        Text(FinanceStrings.cardDisputeUnrecognizedNote)
                            .font(.caption).foregroundStyle(AppColors.statusWarning)
                    }
                }

                Section(FinanceStrings.returnReason) {
                    TextField(FinanceStrings.returnReason, text: $reasonKey)
                    TextField(FinanceStrings.returnComment, text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    CustomButton(title: FinanceStrings.cardOpenDispute) { onSubmit(request) }
                    .disabled(!request.isSubmittable)
                }
            .financeActionRow()
            }
            .navigationTitle(FinanceStrings.cardOpenDispute)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(FinanceStrings.cancel, action: onDismiss)
                }
            }
        }
    }

    private func kindLabel(_ kind: CardDisputeKind) -> String {
        switch kind {
        case .unrecognized:       return FinanceStrings.cardDisputeUnrecognized
        case .serviceNotReceived: return FinanceStrings.cardDisputeNotReceived
        case .notAsDescribed:     return FinanceStrings.cardDisputeNotAsDescribed
        case .duplicate:          return FinanceStrings.cardDisputeDuplicate
        case .incorrectAmount:    return FinanceStrings.cardDisputeIncorrectAmount
        case .refundNotReceived:  return FinanceStrings.cardDisputeRefundMissing
        }
    }
}

extension CardDisputeRequest: Identifiable {
    public var id: String { "\(transactionID)-\(kind.rawValue)" }
}

struct CardTransactionStateBadge: View {
    let state: CardTransactionState

    var body: some View {
        Label(label, systemImage: icon).font(.caption).foregroundStyle(tint)
    }

    private var label: String {
        switch state {
        case .pending:           return FinanceStrings.cardTxPending
        case .authorized:        return FinanceStrings.cardTxAuthorized
        case .declined:          return FinanceStrings.cardTxDeclined
        case .captured:          return FinanceStrings.cardTxCaptured
        case .settled:           return FinanceStrings.cardTxSettled
        case .reversed:          return FinanceStrings.cardTxReversed
        case .refunded:          return FinanceStrings.cardTxRefunded
        case .partiallyRefunded: return FinanceStrings.cardTxPartiallyRefunded
        case .disputed:          return FinanceStrings.cardTxDisputed
        case .chargedBack:       return FinanceStrings.cardTxChargedBack
        case .expired:           return FinanceStrings.cardTxExpired
        case .unknown:           return FinanceStrings.cardTxUnknown
        }
    }

    private var icon: String {
        switch state {
        case .pending, .unknown:            return "clock"
        case .authorized:                   return "lock.circle"
        case .declined:                     return "xmark.octagon"
        case .captured, .settled:           return "checkmark.circle"
        case .reversed, .expired:           return "arrow.uturn.backward"
        case .refunded, .partiallyRefunded: return "arrow.uturn.left.circle"
        case .disputed, .chargedBack:       return "exclamationmark.bubble"
        }
    }

    private var tint: Color {
        switch state {
        case .settled:                                return AppColors.statusSuccess
        case .authorized, .pending, .unknown:         return AppColors.statusWarning
        case .declined, .reversed, .expired:          return .secondary
        case .disputed, .chargedBack:                 return AppColors.statusWarning
        default:                                      return .primary
        }
    }
}
