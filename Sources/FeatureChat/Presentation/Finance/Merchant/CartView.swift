//
//  CartView.swift
//  FeatureChat
//
//  Panier et passage de commande — Bloc 1, chapitre 7.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Le panier, tel que le serveur le tient.
///
/// Les totaux affichés viennent du panier renvoyé, jamais d'une somme faite
/// ici : deux totaux qui divergent d'un centime suffisent à faire perdre
/// confiance dans les deux.
struct CartView: View {

    let merchantID: String
    let commerce: any CommerceOrdering
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @Environment(\.financeFlowSurface) private var surface
    @State private var showsOrder = false
    @State private var phase: Phase = .loading
    @State private var selectedDelivery: String?
    @State private var isMutating = false

    private enum Phase {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case loading
        case empty
        case loaded(CommerceCart)
        case reviewing(CommerceCart)
        case placing
        case placed(CommerceOrder)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        if isMutating { return true }
        switch phase {
        case .placing: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        false
    }

    private var flowBack: (() -> Void)? {
        if case .reviewing(let cart) = phase { return { phase = .loaded(cart) } }
        return nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading: FinanceProgress(label: FinanceStrings.cartLoading)
                case .empty:   FinanceMessage(icon: "cart", text: FinanceStrings.cartEmpty)
                case .loaded(let cart): content(cart)
                case .reviewing(let cart): review(cart)
                case .placing: FinanceProgress(label: FinanceStrings.cartPlacing)
                case .placed(let order): placed(order)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: { Task { await placeOrder() } },
                                                onDismiss: onDismiss)
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.cartTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    // MARK: - Chargement et mutations

    private func load() async {
        phase = .loading
        switch await commerce.cart(merchantID: merchantID) {
        case .success(let cart?):
            selectedDelivery = selectedDelivery ?? cart.deliveryOptions.first?.id
            phase = cart.lines.isEmpty ? .empty : .loaded(cart)
        case .success(nil):
            phase = .empty
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Change la quantité d'une ligne. `0` retire la ligne.
    private func setQuantity(_ quantity: Int, for line: CommerceCartLine) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }

        let submissionKey102 = await operationKeys.key(for: FinanceOperationKeys.scope("cart.update", merchantID, line.itemID, max(0, quantity)), deviceID: deviceID)
        let result = await commerce.updateCart(
            merchantID: merchantID, itemID: line.itemID, quantity: max(0, quantity),
            idempotency: submissionKey102
        )
        switch result {
        case .success(let cart): phase = cart.lines.isEmpty ? .empty : .loaded(cart)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Passe la commande. **Ne paie pas** : la commande créée attend son
    /// paiement, ce qui laisse le stock se réserver et le total se figer avant
    /// que l'argent bouge.
    private func placeOrder() async {
        switch phase {
        case .reviewing, .uncertain: break
        default: return
        }
        guard !isMutating else { return }
        phase = .placing
        let submissionKey118 = await operationKeys.key(for: FinanceOperationKeys.scope("cart.placeOrder", merchantID, String(describing: selectedDelivery)), deviceID: deviceID)
        let result = await commerce.placeOrder(
            merchantID: merchantID, deliveryOptionID: selectedDelivery, noteKey: nil,
            idempotency: submissionKey118
        )
        switch result {
        case .success(let order): phase = .placed(order)
        case .failure(let error) where FinancialOutcomeRoute.isFinalityUnknown(error):
            // Aucune commande à relire : renvoyée sous la même clé, elle fait
            // rendre la commande d'origine si celle-ci a été créée.
            phase = .uncertain(nil)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func content(_ cart: CommerceCart) -> some View {
        Form {
            Section {
                ForEach(cart.lines) { line in
                    lineRow(line)
                }
            }

            if !cart.deliveryOptions.isEmpty {
                Section(FinanceStrings.cartDelivery) {
                    Picker(FinanceStrings.cartDelivery, selection: $selectedDelivery) {
                        ForEach(cart.deliveryOptions) { option in
                            VStack(alignment: .leading) {
                                Text(option.labelKey)
                                if let days = option.estimatedDays {
                                    Text(String(format: FinanceStrings.cartDeliveryDays, days))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .tag(Optional(option.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }

            // Ventilation ligne à ligne, telle que rendue par le serveur.
            Section(FinanceStrings.detailSection) {
                LabeledContent(FinanceStrings.cartSubtotal, value: money(cart.subtotal))
                if let fee = cart.deliveryFee {
                    LabeledContent(FinanceStrings.cartDeliveryFee, value: money(fee))
                }
                if let tax = cart.taxTotal {
                    LabeledContent(FinanceStrings.cartTax, value: money(tax))
                }
                LabeledContent(FinanceStrings.total) {
                    Text(money(cart.total)).font(.body.weight(.semibold)).monospacedDigit()
                }
            }

            // Ce qui bloque la commande est dit, pas seulement grisé : un bouton
            // inerte sans motif fait relancer le support.
            if !cart.blockingReasonKeys.isEmpty {
                Section {
                    ForEach(cart.blockingReasonKeys, id: \.self) { reason in
                        Label(reason, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(AppColors.statusWarning)
                    }
                }
            }

            Section {
                CustomButton(title: FinanceStrings.flowReview) { phase = .reviewing(cart) }
                .disabled(!cart.isOrderable || isMutating)
                .financeActionRow()
            } footer: {
                Text(FinanceStrings.cartPlaceOrderNote).font(.caption)
            }
        }
    }

    private func lineRow(_ line: CommerceCartLine) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.nameKey).font(.subheadline)
                Text("\(money(line.unitPrice)) × \(line.quantity)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                // Une hausse silencieuse entre l'ajout et le paiement est ce qui
                // transforme un achat en réclamation.
                if line.priceChangedSinceAdded {
                    Label(FinanceStrings.cartPriceChanged, systemImage: "arrow.up.right")
                        .font(.caption2).foregroundStyle(AppColors.statusWarning)
                }
            }
            Spacer()
            Text(money(line.lineTotal)).font(.subheadline).monospacedDigit()

            Stepper(
                value: Binding(
                    get: { line.quantity },
                    set: { newValue in Task { await setQuantity(newValue, for: line) } }
                ),
                in: 0...99
            ) { EmptyView() }
            .labelsHidden()
            .disabled(isMutating)
            .accessibilityLabel(FinanceStrings.cartQuantity)
        }
        .padding(.vertical, 2)
    }

    private func review(_ cart: CommerceCart) -> some View {
        FinancePage {
            Text(FinanceStrings.flowReview).font(.title2.bold())
            ForEach(cart.lines) { line in
                lineRow(line).disabled(true)
            }
            LabeledContent(FinanceStrings.total, value: money(cart.total))
            if let delivery = cart.deliveryOptions.first(where: { $0.id == selectedDelivery }) {
                Text(delivery.labelKey)
            }
        } actions: {
            CustomButton(title: FinanceStrings.cartPlaceOrder) { Task { await placeOrder() } }
        }
    }

    private func placed(_ order: CommerceOrder) -> some View {
        FinancePage {
            Text(FinanceStrings.cartPlacedTitle).font(.title2.bold())
            Text(String(format: FinanceStrings.cartPlacedDetail, money(order.total)))
                .foregroundStyle(.secondary)
            LabeledContent(FinanceStrings.receiptReference, value: order.id).textSelection(.enabled)
        } actions: {
            if surface != nil {
                CustomButton(title: FinanceStrings.detailSection) { showsOrder = true }
            }
            Button(FinanceStrings.close, action: onDismiss)
        }
        .financeDestination(isPresented: $showsOrder) {
            if let surface {
                OrderDetailView(orderID: order.id, commerce: commerce, stepUp: surface.stepUp,
                                deviceID: deviceID, onDismiss: { showsOrder = false })
            }
        }
    }

    private func money(_ value: Money) -> String {
        AmountEntry.format(value.majorUnitsForDisplay, value.currency.code)
    }
}
