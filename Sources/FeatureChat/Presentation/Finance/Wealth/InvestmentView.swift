//
//  InvestmentView.swift
//  FeatureChat
//
//  Investissement — Bloc 5, chapitre 41.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Catalogue de produits, gating de profil, souscription.
///
/// **Sans profil investisseur établi, rien n'est souscriptible.** Le gating
/// appartient au backend ; cette vue ne propose pas ce qu'il refusera, et
/// n'affiche jamais une performance passée comme une promesse.
struct InvestmentView: View {

    let trading: any InvestmentTrading
    /// Satisfait le niveau exigé pour engager des fonds sur un produit.
    let stepUp: any StepUpAuthenticating
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var hasAcknowledgedRisk = false
    @State private var amountText = ""
    @State private var selectedProductID: String?
    @State private var showsPortfolio = false
    /// L'ordre qui vient d'être passé, pour en montrer la suite.
    @State private var placedOrderID: String?

    private enum Phase: Equatable {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case loading
        case noProfile
        case empty
        case loaded([InvestmentProduct], InvestorProfile)
        case ordering
        case reviewing(InvestmentOrderDraft, [InvestmentProduct], InvestorProfile)
        /// Ordre composé, authentification à satisfaire.
        case awaitingStepUp(InvestmentOrderDraft, [InvestmentProduct], InvestorProfile)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .ordering: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .loaded, .reviewing, .awaitingStepUp: return !amountText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .reviewing(_, let products, let profile): return { phase = .loaded(products, profile) }
        case .awaitingStepUp(let draft, let products, let profile): return { phase = .reviewing(draft, products, profile) }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading:   FinanceProgress(label: FinanceStrings.hubLoading)
                case .noProfile: FinanceMessage(icon: "person.badge.shield.checkmark",
                                                text: FinanceStrings.investmentNoProfile)
                case .empty:     FinanceMessage(icon: "chart.line.uptrend.xyaxis",
                                                text: FinanceStrings.investmentNoProduct)
                case .loaded(let products, let profile): list(products, profile)
                case .reviewing(let draft, let products, let profile): review(draft, products, profile)
                case .ordering:  FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .awaitingStepUp(let draft, let products, let profile):
                    gate(draft, products, profile)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: { Task { await load() } },
                                                onDismiss: onDismiss)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.investmentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsPortfolio = true } label: {
                        Label(FinanceStrings.portfolioTitle, systemImage: "chart.pie")
                    }
                }
            }
            .financeDestination(item: Binding(
                get: { placedOrderID.map(IdentifiedString.init) },
                set: { if $0 == nil { placedOrderID = nil } }
            )) { wrapper in
                InvestmentOrderView(
                    orderID: wrapper.value, trading: trading, deviceID: deviceID,
                    onDismiss: { placedOrderID = nil }
                )
            }
            .financeDestination(isPresented: $showsPortfolio) {
                PortfolioView(
                    trading: trading, deviceID: deviceID,
                    onDismiss: { showsPortfolio = false; Task { await load() } }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        // Le profil d'abord : sans lui, le catalogue n'a pas à être affiché.
        // Montrer des produits qu'on ne peut pas souscrire crée une attente que
        // le gating décevra.
        guard case .success(let maybeProfile) = await trading.investorProfile(),
              let profile = maybeProfile, profile.isValid() else {
            phase = .noProfile
            return
        }

        switch await trading.products() {
        case .success(let products):
            phase = products.isEmpty ? .empty : .loaded(products, profile)
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    /// Passe l'ordre de souscription.
    ///
    /// La reconnaissance du risque porte sur **la version du document** affichée,
    /// pas sur un accord général : une divulgation révisée depuis n'est plus
    /// celle que l'utilisateur a lue.
    private func subscribe(_ product: InvestmentProduct) async {
        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else { return }

        let draft = InvestmentOrderDraft(
            productID: product.id, side: .subscribe,
            // L'exposant vient du produit, pas d'une constante : le supposer
            // nul divisait par cent tout montant en devise à deux décimales.
            amount: Money(minorUnits: NSDecimalNumber(decimal: amount).int64Value,
                          currency: CurrencyCode(code: product.currency,
                                                 exponent: product.exponent)),
            riskDisclosureVersion: product.documentIDs.first ?? "v1",
            hasAcknowledgedRisk: hasAcknowledgedRisk
        )
        guard draft.isSubmittable else { return }

        // On s'arrête ici : l'ordre est composé, il reste à prouver qui le
        // passe. Le contexte est conservé pour pouvoir revenir au catalogue.
        if case .loaded(let products, let profile) = phase {
            phase = .reviewing(draft, products, profile)
        }
    }

    private func send(_ draft: InvestmentOrderDraft, attestation: StepUpAttestation?) async {
        guard case .awaitingStepUp = phase else { return }
        phase = .ordering
        let submissionKey164 = await operationKeys.key(for: FinanceOperationKeys.scope("investment.placeOrder", String(describing: draft)), deviceID: deviceID)
        let result = await trading.placeOrder(
            draft, idempotency: submissionKey164,
            stepUp: attestation
        )
        switch result {
        case .success(let order):
            // On ouvre l'ordre plutôt que de revenir au catalogue : un ordre
            // passé n'est pas un ordre exécuté, et l'écran doit le dire.
            placedOrderID = order.id
            await load()
        case .failure(let e) where FinancialOutcomeRoute.isFinalityUnknown(e):
            // L'ordre a peut-être été passé : relire le portefeuille le dit.
            // Un échec affiché ferait repasser un second ordre.
            phase = .uncertain(nil)
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func review(_ draft: InvestmentOrderDraft,
                        _ products: [InvestmentProduct], _ profile: InvestorProfile) -> some View {
        FinancePage {
            Text(products.first(where: { $0.id == draft.productID })?.name ?? draft.productID)
                .font(.title2.bold())
            FinanceAmountSummary(title: FinanceStrings.amount,
                                 value: AmountEntry.format(draft.amount.majorUnitsForDisplay, draft.amount.currency.code))
            Text(FinanceStrings.investmentRiskAck).font(.subheadline)
            Text(FinanceStrings.investmentPastPerformance).foregroundStyle(.secondary)
        } actions: {
            CustomButton(title: FinanceStrings.investmentSubscribe) {
                phase = .awaitingStepUp(draft, products, profile)
            }
        }
    }

    private func gate(_ draft: InvestmentOrderDraft,
                      _ products: [InvestmentProduct],
                      _ profile: InvestorProfile) -> some View {
        StepUpGate(
            authenticator: stepUp,
            // Plancher pour un engagement sur un produit d'investissement.
            requiredLevel: .biometric,
            reason: FinanceStrings.stepUpReasonInvestment,
            correlationID: CorrelationId(),
            deviceID: deviceID,
            onSatisfied: { attestation in
                Task { await send(draft, attestation: attestation) }
            },
            onCancel: { phase = .reviewing(draft, products, profile) }
        )
    }

    private func list(_ products: [InvestmentProduct], _ profile: InvestorProfile) -> some View {
        List {
            ForEach(products) { product in
                Section(product.name) {
                    LabeledContent(FinanceStrings.investmentRisk, value: product.riskLevelKey)

                    ForEach(product.feeKeys, id: \.self) { fee in
                        Text(fee).font(.caption).foregroundStyle(.secondary)
                    }

                    if !product.pastPerformanceKeys.isEmpty {
                        ForEach(product.pastPerformanceKeys, id: \.self) { key in
                            Text(key).font(.caption)
                        }
                        // **Obligatoire**, et jamais optionnel : présenter une
                        // performance future comme garantie est interdit (§14).
                        Text(FinanceStrings.investmentPastPerformance)
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    if product.isSuitable(for: profile) {
                        HStack {
                            TextField("0", text: Binding(
                                get: { selectedProductID == product.id ? amountText : "" },
                                set: { amountText = $0; selectedProductID = product.id }
                            ))
                            .keyboardType(.decimalPad)
                            .accessibilityLabel(FinanceStrings.amount)
                            Text(product.currency).foregroundStyle(.secondary)
                        }
                        Toggle(FinanceStrings.investmentRiskAck, isOn: $hasAcknowledgedRisk)
                            .font(.caption)
                        CustomButton(title: FinanceStrings.flowReview) {
                            Task { await subscribe(product) }
                        }
                        // Trois conditions : montant saisi sur **ce** produit,
                        // risque reconnu, et produit adapté au profil.
                        .disabled(!hasAcknowledgedRisk
                                  || selectedProductID != product.id
                                  || amountText.isEmpty)
                    } else {
                        Label(FinanceStrings.investmentNotSuitable, systemImage: "hand.raised")
                            .font(.caption).foregroundStyle(AppColors.statusWarning)
                    }
                }
            }
        }
    }
}


/// Enveloppe `Identifiable` pour présenter une feuille à partir d'un simple
/// identifiant. `String` n'est pas `Identifiable`, et le rendre tel
/// globalement ferait de n'importe quelle chaîne une donnée de présentation.
struct IdentifiedString: Identifiable {
    let value: String
    var id: String { value }

    init(_ value: String) { self.value = value }
}
