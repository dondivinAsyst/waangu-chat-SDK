//
//  CreditView.swift
//  FeatureChat
//
//  Crédit : découverte, simulation, demande — Bloc 5, chapitres 38 et 39.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Parcourt le catalogue de crédit, simule et dépose une demande.
///
/// **Aucun nombre n'est calculé ici** : mensualité, coût total et taux effectif
/// viennent du prêteur. Le client affiche, et il n'affiche jamais une simulation
/// comme une offre — `isIndicativeOnly` est là pour que ce ne soit pas un oubli
/// possible.
struct CreditView: View {

    let lending: any CreditLending
    /// Satisfait le niveau exigé pour s'engager sur un crédit.
    let stepUp: any StepUpAuthenticating
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var products: [CreditProduct] = []
    @State private var amountText = ""
    @State private var termText = "12"
    @State private var hasConsented = false
    @State private var hasAcceptedOffer = false
    /// Éligibilité indicative par produit, chargée à la demande.
    @State private var eligibility: [String: CreditEligibility] = [:]
    @State private var earlyRepayment: FinancialQuote?
    @State private var isLoadingEarlyRepayment = false

    private enum Phase: Equatable {
        case loading
        case noProduct
        case browsing
        case simulating(CreditProduct)
        case simulated(CreditProduct, CreditSimulation)
        case applying
        case applied(CreditApplication)
        /// Offre acceptée par l'utilisateur, authentification à satisfaire.
        case awaitingStepUp(CreditApplication, CreditOffer)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .simulating, .applying: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .browsing, .simulated, .awaitingStepUp: return !amountText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .simulated: return { phase = .browsing }
        case .awaitingStepUp(let application, _): return { phase = .applied(application) }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading:      FinanceProgress(label: FinanceStrings.hubLoading)
                case .noProduct:    FinanceMessage(icon: "banknote", text: FinanceStrings.creditNoProduct)
                case .browsing:     catalogue
                case .simulating:   FinanceProgress(label: FinanceStrings.hubLoading)
                case .simulated(let p, let s): simulation(p, s)
                case .applying:     FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .applied(let a): applied(a)
                case .awaitingStepUp(let a, let o): gate(a, o)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.creditTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await lending.catalog() {
        case .success(let list):
            products = list
            phase = list.isEmpty ? .noProduct : .browsing
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func simulate(_ product: CreditProduct) async {
        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0, let term = Int(termText), term > 0 else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }
        phase = .simulating(product)
        switch await lending.simulate(
            CreditSimulationRequest(productID: product.id, amount: amount, termMonths: term)
        ) {
        case .success(let simulation): phase = .simulated(product, simulation)
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func apply(_ product: CreditProduct, _ simulation: CreditSimulation) async {
        let draft = CreditApplicationDraft(
            productID: product.id, amount: simulation.amount,
            termMonths: simulation.termMonths,
            hasConsentedToDataSharing: hasConsented,
            consentVersion: product.disclosureDocumentID ?? "v1"
        )
        guard draft.isSubmittable else { return }

        phase = .applying
        let submissionKey130 = await operationKeys.key(for: FinanceOperationKeys.scope("credit.apply", String(describing: draft)), deviceID: deviceID)
        switch await lending.apply(draft, idempotency: submissionKey130) {
        case .success(let application): phase = .applied(application)
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    /// Demande l'éligibilité pour un produit.
    ///
    /// Un échec est silencieux : l'éligibilité est un confort, et faire
    /// basculer tout l'écran en erreur parce qu'elle n'a pas répondu
    /// empêcherait de simuler, ce qui, lui, fonctionne encore.
    private func checkEligibility(_ product: CreditProduct) async {
        if case .success(let verdict) = await lending.eligibility(productID: product.id) {
            eligibility[product.id] = verdict
        }
    }

    /// Redemande l'état de la demande au prêteur.
    private func refreshApplication(_ application: CreditApplication) async {
        if case .success(let fresh) = await lending.application(application.id) {
            phase = .applied(fresh)
        }
    }

    /// Devis de remboursement anticipé — **calculé par le prêteur**.
    ///
    /// Estimer localement le solde restant dû reviendrait à recalculer des
    /// intérêts courus sans connaître ni la date de valeur ni les pénalités.
    private func loadEarlyRepayment(_ application: CreditApplication) async {
        isLoadingEarlyRepayment = true
        defer { isLoadingEarlyRepayment = false }

        if case .success(let quote) = await lending.earlyRepaymentQuote(creditID: application.id) {
            earlyRepayment = quote
        }
    }

    @ViewBuilder
    private func eligibilityRow(_ verdict: CreditEligibility) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(
                verdict.isLikelyEligible
                    ? FinanceStrings.creditLikelyEligible
                    : FinanceStrings.creditUnlikelyEligible,
                systemImage: verdict.isLikelyEligible ? "checkmark.circle" : "minus.circle"
            )
            .font(.caption)
            .foregroundStyle(verdict.isLikelyEligible ? Color.primary : Color.secondary)

            // Des facteurs explicables, jamais un score brut : « 62/100 » sans
            // le cadre du prêteur invite à des conclusions injustifiables.
            ForEach(verdict.factorKeys, id: \.self) { key in
                Text("• \(key)").font(.caption2).foregroundStyle(.secondary)
            }
            if !verdict.missingDocumentKeys.isEmpty {
                Text(FinanceStrings.creditMissingDocuments)
                    .font(.caption2).foregroundStyle(AppColors.statusWarning)
                ForEach(verdict.missingDocumentKeys, id: \.self) { key in
                    Text("• \(key)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(FinanceStrings.creditEligibilityIndicative)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var catalogue: some View {
        List {
            Section(FinanceStrings.amount) {
                HStack {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.amount)
                }
                HStack {
                    Text(FinanceStrings.creditTerm)
                    Spacer()
                    TextField("12", text: $termText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel(FinanceStrings.creditTerm)
                }
            }

            ForEach(products) { product in
                Section(product.lenderDisplayName) {
                    LabeledContent(FinanceStrings.creditAmount, value: AmountEntry.format(product.minAmount, product.currency) + " – " + AmountEntry.format(product.maxAmount, product.currency))
                    LabeledContent(FinanceStrings.creditTerm,
                                   value: "\(product.minTermMonths) – \(product.maxTermMonths)")
                    // Taux **affiché**, à titre indicatif. Le taux contractuel
                    // est celui de l'offre, et lui seul engage.
                    if let rate = product.displayedRatePercent {
                        LabeledContent(FinanceStrings.creditRate, value: "\(rate) %")
                    }
                    // Éligibilité **indicative** : elle n'engage pas le
                    // prêteur et se présente comme telle. Un « éligible »
                    // affiché comme un accord fait préparer des documents pour
                    // un refus.
                    if let verdict = eligibility[product.id] {
                        eligibilityRow(verdict)
                    } else {
                        Button(FinanceStrings.creditCheckEligibility) {
                            Task { await checkEligibility(product) }
                        }
                        .font(.caption)
                    }

                    Button(FinanceStrings.creditSimulate) {
                        Task { await simulate(product) }
                    }
                }
            }
        }
    }

    private func simulation(_ product: CreditProduct, _ sim: CreditSimulation) -> some View {
        Form {
            Section {
                // **L'avertissement passe en premier.** Une simulation lue comme
                // une offre fait espérer un crédit que personne n'a accordé.
                Label(FinanceStrings.creditIndicative, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(AppColors.statusWarning)
            }

            Section(FinanceStrings.detailSection) {
                LabeledContent(FinanceStrings.amount, value: AmountEntry.format(sim.amount, sim.currency))
                LabeledContent(FinanceStrings.creditTerm, value: "\(sim.termMonths)")
                LabeledContent(FinanceStrings.creditMonthly,
                               value: AmountEntry.format(sim.monthlyPayment, sim.currency))
                LabeledContent(FinanceStrings.creditTotalCost,
                               value: AmountEntry.format(sim.totalCost, sim.currency))
                LabeledContent(FinanceStrings.creditRate, value: "\(sim.effectiveRatePercent) %")
            }

            Section {
                Toggle(FinanceStrings.creditConsent, isOn: $hasConsented)
                    .font(.subheadline)
                CustomButton(title: FinanceStrings.creditApply) {
                    Task { await apply(product, sim) }
                }
                // Sans consentement au partage des données, aucune demande.
                .disabled(!hasConsented)
            }
        }
    }

    /// Accepte l'offre. **Le consentement porte sur la version du texte de
    /// cette offre**, pas sur une acceptation générale : une offre modifiée
    /// depuis n'est plus celle que l'utilisateur a lue.
    private func accept(_ application: CreditApplication, _ offer: CreditOffer,
                        attestation: StepUpAttestation?) async {
        phase = .applying
        let submissionKey287 = await operationKeys.key(for: FinanceOperationKeys.scope("credit.accept", application.id, offer.id, offer.consentVersion), deviceID: deviceID)
        let result = await lending.acceptOffer(
            applicationID: application.id,
            offerID: offer.id,
            consentVersion: offer.consentVersion,
            idempotency: submissionKey287,
            stepUp: attestation
        )
        switch result {
        case .success(let updated): phase = .applied(updated)
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func gate(_ application: CreditApplication, _ offer: CreditOffer) -> some View {
        StepUpGate(
            authenticator: stepUp,
            // Plancher pour un engagement de crédit.
            requiredLevel: .biometric,
            reason: FinanceStrings.stepUpReasonCredit,
            correlationID: CorrelationId(),
            deviceID: deviceID,
            onSatisfied: { attestation in
                Task { await accept(application, offer, attestation: attestation) }
            },
            // Annuler ne renonce pas à l'offre : on revient à sa lecture.
            onCancel: { phase = .applied(application) }
        )
    }

    private func stateLabel(_ state: CreditApplicationState) -> String {
        switch state {
        case .draft:               return FinanceStrings.creditStateDraft
        case .submitted:           return FinanceStrings.creditStateSubmitted
        case .underReview:         return FinanceStrings.creditStateUnderReview
        case .actionRequired:      return FinanceStrings.creditStateActionRequired
        case .approved:            return FinanceStrings.creditStateApproved
        case .declined:            return FinanceStrings.creditStateDeclined
        case .offerIssued:         return FinanceStrings.creditStateOfferIssued
        case .offerExpired:        return FinanceStrings.creditStateOfferExpired
        case .accepted:            return FinanceStrings.creditStateAccepted
        case .disbursementPending: return FinanceStrings.creditStateDisbursementPending
        case .active:              return FinanceStrings.creditStateActive
        case .closed:              return FinanceStrings.creditStateClosed
        }
    }

    private func applied(_ application: CreditApplication) -> some View {
        Form {
            Section {
                LabeledContent(FinanceStrings.creditApplicationState,
                               value: stateLabel(application.state))
                LabeledContent(FinanceStrings.remittanceUpdatedAt,
                               value: application.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                Button {
                    Task { await refreshApplication(application) }
                } label: {
                    Label(FinanceStrings.remittanceRefresh, systemImage: "arrow.clockwise")
                }
                .disabled(application.state.isTerminal)
            }
            if !application.requiredActionKeys.isEmpty {
                Section(FinanceStrings.creditExpectedDocuments) {
                    ForEach(application.requiredActionKeys, id: \.self) { key in
                        Label(key, systemImage: "doc.badge.plus").font(.subheadline)
                    }
                }
            }
            if let offer = application.offer {
                Section(FinanceStrings.creditOffer) {
                    LabeledContent(FinanceStrings.creditApprovedAmount,
                                   value: AmountEntry.format(offer.approvedAmount, offer.currency))
                    LabeledContent(FinanceStrings.creditRate, value: "\(offer.ratePercent) %")
                    LabeledContent(FinanceStrings.creditTotalCost,
                                   value: AmountEntry.format(offer.totalCost, offer.currency))
                    if let insurance = offer.insuranceAmount {
                        LabeledContent(FinanceStrings.creditInsurance, value: AmountEntry.format(insurance, offer.currency))
                    }
                    ForEach(offer.fees, id: \.labelKey) { fee in
                        LabeledContent(fee.labelKey, value: AmountEntry.format(fee.amount, fee.currency))
                    }

                    if offer.isExpired() {
                        Label(FinanceStrings.creditOfferExpired, systemImage: "clock.badge.xmark")
                            .font(.caption).foregroundStyle(AppColors.statusWarning)
                    }
                }

                // L'échéancier vient du prêteur — jamais recomposé ici.
                if !offer.schedule.isEmpty {
                    Section(FinanceStrings.creditSchedule) {
                        ForEach(offer.schedule, id: \.number) { instalment in
                            HStack {
                                Text("#\(instalment.number)")
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(AmountEntry.format(instalment.total, offer.currency))
                                    Text(instalment.dueDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if !offer.penaltyKeys.isEmpty || !offer.collateralKeys.isEmpty {
                    Section(FinanceStrings.creditConditions) {
                        ForEach(offer.collateralKeys + offer.penaltyKeys, id: \.self) { key in
                            Text(key).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // Un crédit en cours peut se solder par anticipation. Le
                // devis vient du prêteur : le solde restant dû dépend de la
                // date de valeur et des pénalités, qu'on ne connaît pas ici.
                if application.state == .active {
                    Section(FinanceStrings.creditEarlyRepayment) {
                        if let quote = earlyRepayment {
                            LabeledContent(FinanceStrings.total) {
                                Text(AmountEntry.format(quote.totalDebit, quote.sourceCurrency))
                                    .font(.body.weight(.semibold))
                            }
                            ForEach(quote.fees, id: \.labelKey) { fee in
                                LabeledContent(fee.labelKey,
                                               value: AmountEntry.format(fee.amount, fee.currency))
                            }
                            Text(FinanceStrings.creditEarlyRepaymentNote)
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button(FinanceStrings.creditEarlyRepaymentQuote) {
                                Task { await loadEarlyRepayment(application) }
                            }
                            .disabled(isLoadingEarlyRepayment)
                        }
                    }
                }

                if offer.isAcceptable() {
                    Section {
                        Toggle(FinanceStrings.creditTermsAccept, isOn: $hasAcceptedOffer)
                            .font(.subheadline)
                        CustomButton(title: FinanceStrings.creditAcceptOffer) {
                            phase = .awaitingStepUp(application, offer)
                        }
                        .disabled(!hasAcceptedOffer)
                    } footer: {
                        Text(FinanceStrings.creditAcceptNote)
                            .font(.caption)
                    }
                }
            }
        }
    }
}
