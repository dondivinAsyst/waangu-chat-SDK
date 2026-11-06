//
//  SupportCaseView.swift
//  FeatureChat
//
//  Support corrélé à une transaction — Bloc 1, chapitre 7.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Ouvre un dossier de support déjà rattaché à la transaction.
///
/// L'écran montre **ce qui sera transmis** avant de l'envoyer. Un contexte
/// envoyé à l'insu de l'utilisateur — références du fournisseur, historique des
/// statuts — est une divulgation qu'il n'a pas choisie ; le lui montrer coûte un
/// écran et lui rend la décision.
struct SupportCaseView: View {

    let reference: FinancialReference
    let support: any SupportCaseOpening
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var message = ""

    private enum Phase {
        case loading
        case composing(SupportContextPackage)
        case reviewing(SupportContextPackage)
        case opening
        case opened(SupportCase)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .opening: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing, .reviewing: return !message.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        if case .reviewing(let context) = phase { return { phase = .composing(context) } }
        return nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading:   FinanceProgress(label: FinanceStrings.supportLoading)
                case .opening:   FinanceProgress(label: FinanceStrings.supportOpening)
                case .composing(let context): composer(context)
                case .reviewing(let context): review(context)
                case .opened(let supportCase): opened(supportCase)
                case .failed(let text):
                    FinanceMessage(icon: "exclamationmark.triangle", text: text)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.supportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    // MARK: - Actions

    private func load() async {
        phase = .loading
        switch await support.context(for: reference) {
        case .success(let context): phase = .composing(context)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func open(_ context: SupportContextPackage) async {
        guard case .reviewing = phase, !message.isEmpty else { return }
        phase = .opening
        let submissionKey92 = await operationKeys.key(for: FinanceOperationKeys.scope("support.open", String(describing: context.supportCaseID), message), deviceID: deviceID)
        let result = await support.open(
            contextID: context.supportCaseID, messageText: message,
            idempotency: submissionKey92
        )
        switch result {
        case .success(let supportCase): phase = .opened(supportCase)
        case .failure(let error):       phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func composer(_ context: SupportContextPackage) -> some View {
        FinancePage {
            Text(FinanceStrings.supportYourMessage).font(.largeTitle.bold())
            contextSummary(context)
            TextField(FinanceStrings.supportMessagePlaceholder, text: $message, axis: .vertical)
                .lineLimit(4...10)
                .accessibilityLabel(FinanceStrings.supportYourMessage)
                .padding(DesignTokens.spacingM).cardStyle()
            Text(FinanceStrings.supportContextNote).font(.footnote).foregroundStyle(.secondary)
        } actions: {
            CustomButton(title: FinanceStrings.flowReview) { phase = .reviewing(context) }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func review(_ context: SupportContextPackage) -> some View {
        FinancePage {
            Text(FinanceStrings.flowReview).font(.largeTitle.bold())
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.spacingM).cardStyle()
            contextSummary(context)
            Text(FinanceStrings.supportContextNote).font(.footnote).foregroundStyle(.secondary)
        } actions: {
            CustomButton(title: FinanceStrings.supportOpen) { Task { await open(context) } }
        }
    }

    private func contextSummary(_ context: SupportContextPackage) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingM) {
            Text(FinanceStrings.supportAttachedContext).font(.headline)
            LabeledContent(FinanceStrings.supportObservedStatus,
                           value: FinanceStrings.paymentStatusLabel(context.observedStatus))
            if let intent = context.paymentIntentID {
                LabeledContent(FinanceStrings.supportIntent, value: intent).font(.caption.monospaced())
            }
            if let customer = context.maskedCustomerReference {
                LabeledContent(FinanceStrings.supportCustomer, value: customer)
            }
            LabeledContent(FinanceStrings.supportCorrelation, value: context.correlationID.value)
                .font(.caption.monospaced())
            if !context.statusHistory.isEmpty {
                Divider()
                Text(FinanceStrings.supportHistory).font(.headline)
                ForEach(context.statusHistory, id: \.observedAt) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
                            Text(FinanceStrings.paymentStatusLabel(entry.status)).font(.caption)
                            if let reason = entry.reasonKey { Text(reason).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(entry.observedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(DesignTokens.spacingM).cardStyle()
    }

    private func opened(_ supportCase: SupportCase) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(.tint)
            Text(FinanceStrings.supportOpened).font(.headline)
            Text(supportCase.id)
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
            // Un délai annoncé seulement si le support en promet un.
            if let seconds = supportCase.expectedResponseSeconds {
                Text(String(format: FinanceStrings.supportExpectedResponse, Int(seconds / 3600)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(FinanceStrings.close, action: onDismiss).buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(.top, 48)
    }
}
