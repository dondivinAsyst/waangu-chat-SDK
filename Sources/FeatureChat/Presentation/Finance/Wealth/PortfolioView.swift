//
//  PortfolioView.swift
//  FeatureChat
//
//  Portefeuille et ordres — Bloc 5, chapitre 41.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Ce qu'on détient, et les ordres en cours.
///
/// **Aucune valorisation n'est calculée ici.** Ni le total du portefeuille, ni
/// la plus-value, ni une performance : chaque ligne porte la valorisation
/// rendue par le partenaire et sa date. Additionner deux valorisations datées
/// de jours différents produirait un total qui n'a jamais existé.
struct PortfolioView: View {

    let trading: any InvestmentTrading
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var selectedOrder: InvestmentOrder?

    private enum Phase {
        case loading
        case empty
        case loaded([InvestmentHolding])
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
                case .loading: FinanceProgress(label: FinanceStrings.portfolioLoading)
                case .empty:   FinanceMessage(icon: "chart.pie", text: FinanceStrings.portfolioEmpty)
                case .loaded(let holdings): list(holdings)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.portfolioTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await trading.portfolio() {
        case .success(let holdings):
            phase = holdings.isEmpty ? .empty : .loaded(holdings)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func list(_ holdings: [InvestmentHolding]) -> some View {
        List {
            ForEach(holdings) { holding in
                VStack(alignment: .leading, spacing: 4) {
                    Text(holding.productID).font(.subheadline.weight(.medium))
                    HStack {
                        Text(String(format: FinanceStrings.portfolioUnits, "\(holding.units)"))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(holding.valuation.majorUnitsForDisplay) \(holding.valuation.currency.code)")
                            .font(.subheadline).monospacedDigit()
                    }
                    // La date de valorisation compte autant que le montant :
                    // une valeur de la semaine dernière présentée comme
                    // actuelle est une information fausse.
                    Text(String(format: FinanceStrings.portfolioValuedAt,
                                holding.valuedAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.plain)
    }
}

/// Le détail d'un ordre, et son annulation tant qu'il n'est pas exécuté.
struct InvestmentOrderView: View {

    let orderID: String
    let trading: any InvestmentTrading
    let deviceID: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var isConfirmingCancel = false

    private enum Phase {
        case loading
        case loaded(InvestmentOrder)
        case working
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
                case .loading: FinanceProgress(label: FinanceStrings.orderLoading)
                case .working: FinanceProgress(label: FinanceStrings.orderWorking)
                case .loaded(let order): detail(order)
                case .failed(let m): FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.investmentOrderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await trading.order(orderID) {
        case .success(let order): phase = .loaded(order)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Annule l'ordre. Possible tant qu'il n'a pas atteint un état terminal —
    /// un ordre exécuté ne s'annule pas, il se rachète, ce qui est une autre
    /// opération avec un autre prix.
    private func cancel(_ order: InvestmentOrder) async {
        isConfirmingCancel = false
        phase = .working
        let submissionKey165 = await operationKeys.key(for: FinanceOperationKeys.scope("investment.cancelOrder", order.id), deviceID: deviceID)
        let result = await trading.cancelOrder(
            order.id, idempotency: submissionKey165
        )
        switch result {
        case .success(let cancelled): phase = .loaded(cancelled)
        case .failure(let error):     phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func detail(_ order: InvestmentOrder) -> some View {
        Form {
            Section {
                LabeledContent(FinanceStrings.investmentOrderSide) {
                    Text(order.side == .subscribe
                         ? FinanceStrings.investmentSubscribe
                         : FinanceStrings.investmentRedeem)
                }
                LabeledContent(FinanceStrings.investmentOrderState,
                               value: stateLabel(order.state))
                LabeledContent(FinanceStrings.investmentOrderProduct, value: order.productID)
                Text(order.reference.id)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section(FinanceStrings.detailSection) {
                LabeledContent(
                    FinanceStrings.investmentOrderRequested,
                    value: AmountEntry.format(order.requestedAmount.majorUnitsForDisplay, order.requestedAmount.currency.code)
                )
                // Le montant exécuté peut différer du demandé — exécution
                // partielle. Afficher le demandé comme s'il était exécuté
                // ferait croire à un placement qui n'a eu lieu qu'à moitié.
                if let executed = order.executedAmount {
                    LabeledContent(
                        FinanceStrings.investmentOrderExecuted,
                        value: AmountEntry.format(executed.majorUnitsForDisplay, executed.currency.code)
                    )
                } else {
                    Text(FinanceStrings.investmentOrderNotExecuted)
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent(FinanceStrings.investmentOrderPlacedAt,
                               value: order.placedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if order.executionReceiptID != nil {
                Section(FinanceStrings.investmentOrderReceipt) {
                    Text(order.executionReceiptID ?? "")
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
            }

            Section {
                Button { Task { await load() } } label: {
                    Label(FinanceStrings.remittanceRefresh, systemImage: "arrow.clockwise")
                }
                .disabled(order.state.isTerminal)

                if !order.state.isTerminal {
                    Button(FinanceStrings.investmentOrderCancel, role: .destructive) {
                        isConfirmingCancel = true
                    }
                }
            }
        }
        .confirmationDialog(
            FinanceStrings.investmentOrderCancelTitle,
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button(FinanceStrings.investmentOrderCancel, role: .destructive) {
                Task { await cancel(order) }
            }
            Button(FinanceStrings.cancel, role: .cancel) { isConfirmingCancel = false }
        } message: {
            Text(FinanceStrings.investmentOrderCancelDetail)
        }
    }

    private func stateLabel(_ state: InvestmentOrderState) -> String {
        switch state {
        case .draft:             return FinanceStrings.investmentStateDraft
        case .submitted:         return FinanceStrings.investmentStateSubmitted
        case .pending:           return FinanceStrings.investmentStatePending
        case .partiallyExecuted: return FinanceStrings.investmentStatePartial
        case .executed:          return FinanceStrings.investmentStateExecuted
        case .rejected:          return FinanceStrings.investmentStateRejected
        case .cancelled:         return FinanceStrings.investmentStateCancelled
        }
    }
}
