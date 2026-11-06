//
//  PFMView.swift
//  FeatureChat
//
//  Analyses financières personnelles — Bloc 5, chapitre 42.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Présente les agrégats financiers de l'utilisateur.
///
/// **Aucun total n'est calculé ici.** Additionner des transactions côté client
/// divergerait de la comptabilité dès qu'une opération est en vol, annulée ou
/// remboursée — et l'utilisateur verrait deux chiffres selon l'écran.
struct PFMView: View {

    let pfm: any PersonalFinanceProviding
    /// Nécessaire aux clés d'idempotence des corrections et des budgets.
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var isCreatingBudget = false
    @State private var recategorizing: PFMAnomaly?
    @State private var showsCopilot = false
    /// Opération que le Copilot propose de recatégoriser.
    @State private var proposedOperationID: String?

    private enum Phase: Equatable {
        case loading
        case empty
        case loaded(PFMSummary, [PFMBudget], [PFMAnomaly])
        case failed(String)
    }

    /// Période courante, découpée dans le fuseau de l'appareil.
    ///
    /// Le fuseau accompagne la période : sans lui, « les dépenses de janvier »
    /// n'a pas de sens stable — une opération du 31 à 23 h peut tomber en
    /// février selon l'observateur.
    private var currentPeriod: PFMPeriod {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return PFMPeriod(start: start, end: now,
                         timeZoneIdentifier: TimeZone.current.identifier)
    }

    /// La devise des agrégats en cours. Un budget dans une autre devise que le
    /// résumé produirait une consommation sans rapport avec la limite.
    private var currentCurrency: String {
        if case .loaded(let summary, _, _) = phase { return summary.currency }
        return ""
    }

    /// Les catégories connues du serveur, telles qu'elles apparaissent dans le
    /// résumé. Aucune liste locale : elle divergerait du référentiel.
    private var currentCategories: [PFMCategoryTotal] {
        if case .loaded(let summary, _, _) = phase { return summary.categories }
        return []
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
                case .loading: FinanceProgress(label: FinanceStrings.hubLoading)
                case .empty:   FinanceMessage(icon: "chart.pie", text: FinanceStrings.pfmNoData)
                case .loaded(let summary, let budgets, let anomalies):
                    content(summary, budgets, anomalies)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.pfmTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreatingBudget = true } label: {
                        Label(FinanceStrings.pfmNewBudget, systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showsCopilot = true } label: {
                        Label(FinanceStrings.copilotTitle, systemImage: "sparkles")
                    }
                }
            }
            .financeDestination(isPresented: $showsCopilot) {
                CopilotView(
                    pfm: pfm, period: currentPeriod, deviceID: deviceID,
                    // Le Copilot **propose** ; l'écran ordinaire exécute. La
                    // feuille se ferme et la correction s'ouvre : deux feuilles
                    // empilées laisseraient la première capter les gestes.
                    onRecategorize: { operationID in
                        showsCopilot = false
                        proposedOperationID = operationID
                    },
                    onDismiss: { showsCopilot = false }
                )
            }
            .financeDestination(item: Binding(
                get: { proposedOperationID.map(IdentifiedString.init) },
                set: { if $0 == nil { proposedOperationID = nil } }
            )) { wrapper in
                PFMRecategorizeView(
                    operationID: wrapper.value,
                    categories: currentCategories,
                    pfm: pfm, deviceID: deviceID,
                    onDone: { proposedOperationID = nil; Task { await load() } },
                    onDismiss: { proposedOperationID = nil }
                )
            }
            .financeDestination(isPresented: $isCreatingBudget) {
                PFMBudgetCreationView(
                    pfm: pfm, period: currentPeriod,
                    currency: currentCurrency, deviceID: deviceID,
                    onCreated: { isCreatingBudget = false; Task { await load() } },
                    onDismiss: { isCreatingBudget = false }
                )
            }
            .financeDestination(item: $recategorizing) { anomaly in
                PFMRecategorizeView(
                    operationID: anomaly.operationID ?? "",
                    categories: currentCategories,
                    pfm: pfm, deviceID: deviceID,
                    onDone: { recategorizing = nil; Task { await load() } },
                    onDismiss: { recategorizing = nil }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        let period = currentPeriod
        switch await pfm.summary(period: period) {
        case .failure:
            // Sans agrégat, l'écran est vide — il n'en fabrique pas.
            phase = .empty
        case .success(let summary):
            let budgets = (try? await pfm.budgets().get()) ?? []
            let anomalies = (try? await pfm.anomalies(period: period).get()) ?? []
            phase = .loaded(summary, budgets, anomalies)
        }
    }

    private func content(_ summary: PFMSummary,
                         _ budgets: [PFMBudget],
                         _ anomalies: [PFMAnomaly]) -> some View {
        List {
            Section {
                LabeledContent(FinanceStrings.pfmIncome,
                               value: AmountEntry.format(minorUnits: summary.totalIncomeMinorUnits, summary.currency))
                LabeledContent(FinanceStrings.pfmExpense,
                               value: AmountEntry.format(minorUnits: summary.totalExpenseMinorUnits, summary.currency))
                if let netWorth = summary.netWorthMinorUnits {
                    LabeledContent(FinanceStrings.pfmNetWorth,
                                   value: AmountEntry.format(minorUnits: netWorth, summary.currency))
                }
            } footer: {
                // Dire de quand datent les chiffres : un agrégat sans date se
                // lit comme instantané, ce qu'il n'est pas.
                Text(String(format: FinanceStrings.pfmAsOf, summary.asOf.formatted())).font(.caption)
            }

            if !budgets.isEmpty {
                Section(FinanceStrings.pfmBudgets) {
                    ForEach(budgets) { budget in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(budget.labelKey)
                                Spacer()
                                if budget.isExceeded {
                                    Text(FinanceStrings.pfmBudgetExceeded)
                                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                                }
                            }
                            if let usage = budget.usagePercent {
                                ProgressView(value: min(1, Double(truncating: usage as NSNumber) / 100))
                                    .tint(budget.isExceeded ? AppColors.statusWarning : .accentColor)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !summary.recurringPayments.isEmpty {
                Section(FinanceStrings.pfmRecurring) {
                    ForEach(summary.recurringPayments) { payment in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(payment.merchantLabel)
                                if payment.hasRevocableMandate {
                                    // Signaler ce qui est révocable depuis
                                    // l'application : c'est la différence entre
                                    // subir un prélèvement et pouvoir l'arrêter.
                                    Text(FinanceStrings.pfmRevocable)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(AmountEntry.format(minorUnits: payment.amountMinorUnits, summary.currency))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !anomalies.isEmpty {
                Section(FinanceStrings.pfmAnomalies) {
                    ForEach(anomalies) { anomaly in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(anomaly.explanationKey, systemImage: "exclamationmark.circle")
                                .font(.subheadline)
                            Text(anomaly.detectedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)

                            // Une anomalie vient souvent d'une catégorie
                            // fausse. Corriger sur place évite d'aller
                            // chercher l'opération dans un historique.
                            if anomaly.operationID != nil {
                                Button(FinanceStrings.pfmRecategorize) {
                                    recategorizing = anomaly
                                }
                                .font(.caption)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

// MARK: - Créer un budget

/// Crée un budget sur une période.
///
/// La limite est saisie, jamais suggérée : proposer un montant « d'après vos
/// dépenses » ferait du client l'auteur d'un conseil financier.
struct PFMBudgetCreationView: View {

    let pfm: any PersonalFinanceProviding
    let period: PFMPeriod
    let currency: String
    let deviceID: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onCreated: () -> Void
    let onDismiss: () -> Void

    @State private var label = ""
    @State private var limitText = ""
    @State private var categoryID = ""
    @State private var phase: Phase = .composing

    private enum Phase {
        case composing
        case creating
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .creating: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing: return !label.isEmpty || !limitText.isEmpty || !categoryID.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .composing: form
                case .creating:  FinanceProgress(label: FinanceStrings.pfmCreatingBudget)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.pfmNewBudget)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
    }

    private func create() async {
        guard let limit = Decimal(string: limitText.replacingOccurrences(of: ",", with: ".")),
              limit > 0
        else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }

        phase = .creating
        let draft = PFMBudgetDraft(
            labelKey: label.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryID: categoryID.isEmpty ? nil : categoryID,
            limitMinorUnits: NSDecimalNumber(decimal: limit).int64Value,
            currency: currency,
            period: period
        )
        let submissionKey330 = await operationKeys.key(for: FinanceOperationKeys.scope("pfm.createBudget", String(describing: draft)), deviceID: deviceID)
        switch await pfm.createBudget(draft, idempotency: submissionKey330) {
        case .success: onCreated()
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private var form: some View {
        Form {
            Section(FinanceStrings.pfmBudgetLabel) {
                TextField(FinanceStrings.pfmBudgetLabel, text: $label)
            }
            Section(FinanceStrings.pfmBudgetLimit) {
                HStack {
                    TextField("0", text: $limitText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.pfmBudgetLimit)
                    Text(currency).foregroundStyle(.secondary)
                }
            }
            Section(FinanceStrings.pfmBudgetCategory) {
                TextField(FinanceStrings.pfmBudgetCategoryOptional, text: $categoryID)
            }
            Section {
                CustomButton(title: FinanceStrings.pfmCreateBudget) { Task { await create() } }
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || limitText.isEmpty)
            } footer: {
                Text(FinanceStrings.pfmBudgetPeriodNote).font(.caption)
            }
        }
    }
}

// MARK: - Corriger une catégorie

/// Transmet une correction de catégorie.
///
/// Le client **transmet** la correction, il ne recatégorise rien : les
/// agrégats se recalculent côté serveur, et les recalculer aussi ici ferait
/// diverger deux chiffres pour la même dépense.
struct PFMRecategorizeView: View {

    let operationID: String
    let categories: [PFMCategoryTotal]
    let pfm: any PersonalFinanceProviding
    let deviceID: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDone: () -> Void
    let onDismiss: () -> Void

    @State private var selected: String = ""
    @State private var phase: Phase = .composing

    private enum Phase {
        case composing
        case saving
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .saving: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing: return !selected.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .composing: form
                case .saving:    FinanceProgress(label: FinanceStrings.pfmRecategorizing)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.pfmRecategorize)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
    }

    private func save() async {
        phase = .saving
        let submissionKey425 = await operationKeys.key(for: FinanceOperationKeys.scope("pfm.recategorize", operationID, String(describing: selected)), deviceID: deviceID)
        let result = await pfm.recategorize(
            operationID: operationID, categoryID: selected,
            idempotency: submissionKey425
        )
        switch result {
        case .success: onDone()
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private var form: some View {
        Form {
            // Les catégories viennent des agrégats du serveur : une liste
            // codée en dur ici divergerait du référentiel dès sa première
            // évolution.
            if categories.isEmpty {
                Section {
                    Text(FinanceStrings.pfmNoCategory)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section(FinanceStrings.pfmBudgetCategory) {
                    Picker(FinanceStrings.pfmBudgetCategory, selection: $selected) {
                        Text(FinanceStrings.formNoChoice).tag("")
                        ForEach(categories) { category in
                            Text(category.labelKey).tag(category.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }

            Section {
                CustomButton(title: FinanceStrings.pfmApplyCategory) { Task { await save() } }
                .disabled(selected.isEmpty)
            }
            .financeActionRow()
        }
    }
}
