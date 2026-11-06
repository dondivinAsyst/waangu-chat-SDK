//
//  CopilotView.swift
//  FeatureChat
//
//  Copilot borné — Bloc 5, chapitre 42 (§15, §30).
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Ce que le Copilot peut dire, et rien de plus.
///
/// **Il lit, explique, propose. Il n'exécute pas.** Chaque outil demande un
/// accord explicite avant de toucher aux données, chaque réponse cite les
/// opérations qui l'étayent, et toute suite qui modifierait quelque chose
/// repasse par l'écran ordinaire — politique, confirmation, step-up, backend.
///
/// Une réponse sans source n'est pas affichée : elle n'existe pas. C'est
/// `CopilotAnswer` qui l'empêche de se construire, pas cet écran qui la filtre.
struct CopilotView: View {

    let pfm: any PersonalFinanceProviding
    let period: PFMPeriod
    let deviceID: String
    /// Ouvre la correction de catégorie sur une opération. Le Copilot **propose**
    /// ce geste ; c'est l'écran ordinaire qui l'exécute.
    let onRecategorize: (String) -> Void
    let onDismiss: () -> Void

    @State private var phase: Phase = .idle
    @State private var grantedTools: Set<String> = []

    private enum Phase {
        case idle
        case working
        case answered([CopilotAnswer], [PFMBudget])
        case nothingToSay
        case failed(String)
    }

    private var anomalyTool: PFMAnomalyExplanationTool { .init(pfm: pfm) }
    private var budgetTool: PFMBudgetStatusTool { .init(pfm: pfm) }

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
                case .idle:    consent
                case .working: FinanceProgress(label: FinanceStrings.copilotWorking)
                case .answered(let answers, let budgets): result(answers, budgets)
                case .nothingToSay:
                    FinanceMessage(icon: "checkmark.circle", text: FinanceStrings.copilotNothing)
                case .failed(let m):
                    FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.copilotTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
    }

    // MARK: - Consentement

    /// L'accord se donne **par outil**, et il est nommé.
    ///
    /// Un consentement global « le Copilot peut accéder à mes finances » ne dit
    /// pas ce qui sera lu. Nommer chaque outil et ce qu'il regarde rend le
    /// refus possible sur l'un sans perdre l'autre.
    private var consent: some View {
        Form {
            Section {
                Text(FinanceStrings.copilotIntro).font(.subheadline)
            }

            Section(FinanceStrings.copilotTools) {
                toolToggle(anomalyTool.toolID,
                           label: FinanceStrings.copilotToolAnomalies,
                           detail: FinanceStrings.copilotToolAnomaliesDetail)
                toolToggle(budgetTool.toolID,
                           label: FinanceStrings.copilotToolBudgets,
                           detail: FinanceStrings.copilotToolBudgetsDetail)
            }

            Section {
                CustomButton(title: FinanceStrings.copilotAsk) { Task { await run() } }
                .disabled(grantedTools.isEmpty)
                .financeActionRow()
            } footer: {
                Text(FinanceStrings.copilotReadOnlyNote).font(.caption)
            }
        }
    }

    private func toolToggle(_ toolID: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(label, isOn: Binding(
                get: { grantedTools.contains(toolID) },
                set: { granted in
                    if granted { grantedTools.insert(toolID) }
                    else { grantedTools.remove(toolID) }
                }
            ))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Exécution

    /// N'exécute que les outils autorisés.
    ///
    /// L'autorisation est construite ici et transportée jusqu'à l'outil : c'est
    /// elle qui porte la corrélation, et c'est ce qui rend l'exécution auditable
    /// après coup.
    private func run() async {
        phase = .working
        let correlationID = CorrelationId()

        var answers: [CopilotAnswer] = []
        var budgets: [PFMBudget] = []

        if grantedTools.contains(anomalyTool.toolID) {
            let authorization = ToolAuthorization(
                toolID: anomalyTool.toolID, grantedByUser: true,
                capabilityID: FinancialCapabilityID.pfm, correlationID: correlationID
            )
            do {
                answers = try await anomalyTool.execute(
                    input: .init(period: period), authorization: authorization
                )
            } catch let error as FinanceError {
                phase = .failed(FinanceStrings.errorMessage(error))
                return
            } catch {
                phase = .failed(FinanceStrings.copilotFailed)
                return
            }
        }

        if grantedTools.contains(budgetTool.toolID) {
            let authorization = ToolAuthorization(
                toolID: budgetTool.toolID, grantedByUser: true,
                capabilityID: FinancialCapabilityID.pfm, correlationID: correlationID
            )
            budgets = (try? await budgetTool.execute(
                input: .init(exceededOnly: true), authorization: authorization
            )) ?? []
        }

        phase = (answers.isEmpty && budgets.isEmpty)
            ? .nothingToSay
            : .answered(answers, budgets)
    }

    // MARK: - Résultat

    private func result(_ answers: [CopilotAnswer], _ budgets: [PFMBudget]) -> some View {
        List {
            if !budgets.isEmpty {
                Section(FinanceStrings.copilotExceededBudgets) {
                    ForEach(budgets) { budget in
                        HStack {
                            Text(budget.labelKey)
                            Spacer()
                            Text(AmountEntry.format(minorUnits: budget.spentMinorUnits, budget.currency) + " / " + AmountEntry.format(minorUnits: budget.limitMinorUnits, budget.currency))
                                .font(.caption).monospacedDigit().foregroundStyle(AppColors.statusWarning)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !answers.isEmpty {
                Section(FinanceStrings.copilotFindings) {
                    ForEach(answers, id: \.textKey) { answer in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(answer.textKey).font(.subheadline)

                            // Les sources, montrées. Une réponse financière
                            // qu'on ne peut pas remonter à une opération est
                            // une réponse qu'on ne peut pas contester.
                            Text(FinanceStrings.copilotSources)
                                .font(.caption2).foregroundStyle(.secondary)
                            ForEach(answer.sourceOperationIDs, id: \.self) { operationID in
                                Button {
                                    // Le Copilot propose ; l'écran ordinaire
                                    // exécute. Aucune mutation ne part d'ici.
                                    onRecategorize(operationID)
                                } label: {
                                    Label(operationID, systemImage: "arrow.up.right.square")
                                        .font(.caption.monospaced())
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                Button(FinanceStrings.copilotAskAgain) { phase = .idle }
            } footer: {
                Text(FinanceStrings.copilotProposalNote).font(.caption)
            }
        }
    }
}
