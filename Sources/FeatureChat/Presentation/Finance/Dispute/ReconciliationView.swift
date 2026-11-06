//
//  ReconciliationView.swift
//  FeatureChat
//
//  Incidents et réconciliation — Bloc 6, chapitre 53.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Les dossiers de rapprochement de l'utilisateur.
struct ReconciliationListView: View {

    let reconciliation: any ReconciliationProviding
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var selected: ReconciliationCase?

    private enum Phase {
        case loading
        case empty
        case loaded([ReconciliationCase])
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
                case .loading: FinanceProgress(label: FinanceStrings.reconLoading)
                case .empty:   FinanceMessage(icon: "checkmark.circle", text: FinanceStrings.reconEmpty)
                case .loaded(let list):
                    List(list) { item in
                        Button { selected = item } label: { row(item) }
                            .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.reconTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(item: $selected) { item in
                ReconciliationDetailView(
                    caseID: item.id, reconciliation: reconciliation,
                    deviceID: deviceID,
                    onDismiss: { selected = nil; Task { await load() } }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await reconciliation.cases(cursor: nil) {
        case .success(let list):
            phase = list.isEmpty ? .empty : .loaded(list)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func row(_ item: ReconciliationCase) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(FinanceStrings.reconKindLabel(item.kind)).font(.subheadline.weight(.medium))
                Text(item.openedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
                ReconciliationStateBadge(state: item.state)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let discrepancy = item.discrepancyAmount {
                    Text("\(discrepancy.majorUnitsForDisplay) \(discrepancy.currency.code)")
                        .font(.subheadline).monospacedDigit()
                }
                // Un dossier qui attend l'utilisateur se voit dans la liste :
                // sinon il dort jusqu'à ce que quelqu'un l'ouvre par hasard.
                if item.awaitsUserAction {
                    Text(FinanceStrings.reconAwaitsYou)
                        .font(.caption2).foregroundStyle(AppColors.statusWarning)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// Le détail d'un dossier : qui affirme quoi.
///
/// **L'écran ne tranche pas.** Il montre côte à côte ce que chaque système
/// affirme, et laisse la résolution à qui la détient. Afficher une conclusion
/// locale sur un désaccord entre deux systèmes financiers serait une invention.
struct ReconciliationDetailView: View {

    let caseID: String
    let reconciliation: any ReconciliationProviding
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var snapshots: TruthSnapshotBundle?
    @State private var isLoadingSnapshots = false

    private enum Phase {
        case loading
        case loaded(ReconciliationCase)
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
                case .loading: FinanceProgress(label: FinanceStrings.reconLoading)
                case .loaded(let item): detail(item)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.reconCaseTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        phase = .loading
        switch await reconciliation.caseDetail(id: caseID) {
        case .success(let item): phase = .loaded(item)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func loadSnapshots() async {
        isLoadingSnapshots = true
        defer { isLoadingSnapshots = false }
        if case .success(let bundle) = await reconciliation.truthSnapshots(caseID: caseID) {
            snapshots = bundle
        }
    }

    private func detail(_ item: ReconciliationCase) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(FinanceStrings.reconKindLabel(item.kind)).font(.headline)
                    ReconciliationStateBadge(state: item.state)
                    Text(FinanceStrings.reconKindDetail(item.kind))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section(FinanceStrings.reconSubjects) {
                ForEach(item.subjects, id: \.objectID) { subject in
                    HStack {
                        Text(FinanceStrings.reconSystemLabel(subject.system)).font(.caption)
                        Spacer()
                        Text(subject.objectID)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if let discrepancy = item.discrepancyAmount {
                    LabeledContent(FinanceStrings.reconDiscrepancy) {
                        Text("\(discrepancy.majorUnitsForDisplay) \(discrepancy.currency.code)")
                            .font(.body.weight(.semibold)).monospacedDigit()
                    }
                }
            }

            truthSection()

            if !item.escalations.isEmpty {
                Section(FinanceStrings.reconEscalations) {
                    ForEach(item.escalations) { escalation in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(FinanceStrings.reconPartnerLabel(escalation.target))
                                .font(.subheadline)
                            Text(escalation.statusKey).font(.caption2).foregroundStyle(.secondary)
                            // Un partenaire hors délai se voit : sinon un
                            // dossier dort chez quelqu'un d'autre sans que
                            // personne le relance.
                            if escalation.isOverdue() {
                                Label(FinanceStrings.reconOverdue, systemImage: "clock.badge.exclamationmark")
                                    .font(.caption2).foregroundStyle(AppColors.statusWarning)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if let resolution = item.resolution {
                Section(FinanceStrings.reconResolution) {
                    Text(FinanceStrings.reconOutcomeLabel(resolution.outcome))
                        .font(.subheadline.weight(.medium))
                    Text(resolution.explanationKey).font(.caption).foregroundStyle(.secondary)
                    if let corrective = resolution.correctiveReference {
                        Text(corrective.id)
                            .font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }

            Section {
                // La corrélation omnicanale : c'est ce qu'on donne au support
                // pour retrouver l'incident vu ailleurs.
                LabeledContent(FinanceStrings.reconCorrelation) {
                    Text(item.omnichannelCorrelationID)
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
            } footer: {
                Text(FinanceStrings.reconCorrelationNote).font(.caption)
            }
        }
    }

    @ViewBuilder
    private func truthSection() -> some View {
        Section(FinanceStrings.reconTruths) {
            if let bundle = snapshots {
                // Un système absent n'est pas un système d'accord : c'est un
                // système qui n'a pas répondu.
                if !bundle.isConclusive {
                    Label(FinanceStrings.reconInconclusive, systemImage: "questionmark.circle")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }

                if let financial = bundle.financial {
                    truthRow(
                        system: .ledger,
                        state: FinanceStrings.paymentStatusLabel(financial.status),
                        amount: financial.amount
                    )
                }
                if let merchant = bundle.merchant {
                    truthRow(system: .merchantBackend,
                             state: merchant.merchantStateKey, amount: merchant.amount)
                }
                if let card = bundle.card {
                    truthRow(
                        system: .cardSystem,
                        state: card.state.rawValue, // CI-ALLOW : état carte brut, hors surface financière
                        amount: card.settledAmount ?? card.capturedAmount ?? card.authorizedAmount
                    )
                }

                Text(String(format: FinanceStrings.reconCapturedAt,
                            bundle.capturedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Button(FinanceStrings.reconLoadTruths) { Task { await loadSnapshots() } }
                    .disabled(isLoadingSnapshots)
            }
        }
    }

    private func truthRow(system: TruthSystem, state: String, amount: Money?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(FinanceStrings.reconSystemLabel(system)).font(.caption.weight(.medium))
                Text(state).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let amount {
                Text(AmountEntry.format(amount.majorUnitsForDisplay, amount.currency.code))
                    .font(.caption).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ReconciliationStateBadge: View {
    let state: ReconciliationState

    var body: some View {
        Text(FinanceStrings.reconStateLabel(state))
            .font(.caption2)
            .foregroundStyle(state.isTerminal ? Color.secondary : AppColors.statusWarning)
    }
}
