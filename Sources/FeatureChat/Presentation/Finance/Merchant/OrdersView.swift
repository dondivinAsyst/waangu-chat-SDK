//
//  OrdersView.swift
//  FeatureChat
//
//  Commandes, suivi et après-vente — Bloc 1, chapitre 7.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// La liste des commandes, la plus récente d'abord.
struct OrdersView: View {

    let commerce: any CommerceOrdering
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    let onDismiss: () -> Void

    @State private var orders: [CommerceOrder] = []
    @State private var phase: Phase = .loading
    @State private var selected: CommerceOrder?

    private enum Phase {
        case loading
        case empty
        case loaded
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
                case .loading: FinanceProgress(label: FinanceStrings.ordersLoading)
                case .empty:   FinanceMessage(icon: "shippingbox", text: FinanceStrings.ordersEmpty)
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                case .loaded:
                    List(orders) { order in
                        Button { selected = order } label: { row(order) }
                            .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.ordersTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(item: $selected) { order in
                OrderDetailView(
                    orderID: order.id, commerce: commerce,
                    stepUp: stepUp, deviceID: deviceID,
                    onDismiss: { selected = nil; Task { await load() } }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        phase = .loading
        switch await commerce.orders(cursor: nil) {
        case .success(let list):
            orders = list
            phase = list.isEmpty ? .empty : .loaded
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func row(_ order: CommerceOrder) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(order.merchantNameKey).font(.subheadline.weight(.medium))
                Text(order.placedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
                OrderStateBadge(state: order.state)
            }
            Spacer()
            Text(AmountEntry.format(order.total.majorUnitsForDisplay, order.total.currency.code))
                .font(.subheadline).monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Une commande : lignes, suivi, paiement, annulation, retour.
struct OrderDetailView: View {

    let orderID: String
    let commerce: any CommerceOrdering
    /// Satisfait le niveau exigé pour payer une commande.
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var showsReturn = false

    private enum Phase {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case loading
        case loaded(CommerceOrder)
        /// Paiement demandé, authentification à satisfaire.
        case awaitingStepUp(CommerceOrder)
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
        switch phase {
        case .awaitingStepUp(let order): return { phase = .loaded(order) }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading: FinanceProgress(label: FinanceStrings.ordersLoading)
                case .working: FinanceProgress(label: FinanceStrings.orderWorking)
                case .loaded(let order): detail(order)
                case .awaitingStepUp(let order): gate(order)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: { Task { await load() } },
                                                onDismiss: onDismiss)
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.orderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(isPresented: $showsReturn) {
                if case .loaded(let order) = phase {
                    ReturnRequestView(
                        order: order, commerce: commerce, deviceID: deviceID,
                        onDismiss: { showsReturn = false; Task { await load() } }
                    )
                }
            }
        }
        .financeLoadOnce { await load() }
    }

    // MARK: - Actions

    private func load() async {
        phase = .loading
        switch await commerce.order(id: orderID) {
        case .success(let order): phase = .loaded(order)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func pay(_ order: CommerceOrder, attestation: StepUpAttestation?) async {
        phase = .working
        let submissionKey184 = await operationKeys.key(for: FinanceOperationKeys.scope("order.pay", order.id), deviceID: deviceID)
        let result = await commerce.payOrder(
            orderID: order.id,
            idempotency: submissionKey184,
            stepUp: attestation
        )
        switch result {
        case .success(let updated): phase = .loaded(updated)
        case .failure(let error) where FinancialOutcomeRoute.isFinalityUnknown(error):
            // L'objet porte la vérité : le relire dit si le paiement est passé.
            // Afficher un échec inviterait à payer une seconde fois.
            phase = .uncertain(nil)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func cancel(_ order: CommerceOrder) async {
        phase = .working
        let submissionKey197 = await operationKeys.key(for: FinanceOperationKeys.scope("order.cancel", order.id), deviceID: deviceID)
        let result = await commerce.cancelOrder(
            id: order.id, reasonKey: "USER_REQUESTED",
            idempotency: submissionKey197
        )
        switch result {
        case .success(let updated): phase = .loaded(updated)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func gate(_ order: CommerceOrder) -> some View {
        StepUpGate(
            authenticator: stepUp,
            // Plancher pour le paiement d'une commande.
            requiredLevel: .biometric,
            reason: FinanceStrings.stepUpReasonOrder,
            correlationID: CorrelationId(),
            deviceID: deviceID,
            onSatisfied: { attestation in
                Task { await pay(order, attestation: attestation) }
            },
            // La commande reste passée et impayée : rien n'est perdu.
            onCancel: { phase = .loaded(order) }
        )
    }

    private func detail(_ order: CommerceOrder) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(order.merchantNameKey).font(.headline)
                    OrderStateBadge(state: order.state)
                    // Le lien vers la transaction : sans lui, on ne peut pas
                    // rattacher un reçu à une commande, ni l'inverse.
                    if let reference = order.paymentReference {
                        Text(reference.id)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section(FinanceStrings.orderItems) {
                ForEach(order.lines) { line in
                    HStack {
                        Text("\(line.quantity)× \(line.nameKey)").font(.subheadline)
                        Spacer()
                        Text(AmountEntry.format(line.lineTotal.majorUnitsForDisplay, line.lineTotal.currency.code))
                            .font(.subheadline).monospacedDigit()
                    }
                }
                LabeledContent(FinanceStrings.total) {
                    Text(AmountEntry.format(order.total.majorUnitsForDisplay, order.total.currency.code))
                        .font(.body.weight(.semibold)).monospacedDigit()
                }
            }

            // Le suivi vient du transporteur. Aucune étape n'est déduite de
            // l'état : afficher « expédié » parce que la commande est payée
            // ferait attendre un colis que personne n'a remis.
            if !order.trackingEvents.isEmpty {
                Section(FinanceStrings.orderTracking) {
                    ForEach(order.trackingEvents) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7)).foregroundStyle(.tint)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.labelKey).font(.subheadline)
                                Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                                if let location = event.locationKey {
                                    Text(location).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section {
                if order.state == .awaitingPayment {
                    CustomButton(title: FinanceStrings.orderPay) { phase = .awaitingStepUp(order) }
                }
                if order.isCancellable() {
                    Button(FinanceStrings.orderCancel, role: .destructive) {
                        Task { await cancel(order) }
                    }
                }
                if order.isReturnable() {
                    Button(FinanceStrings.orderReturn) { showsReturn = true }
                }
            }
        }
    }
}

/// L'état d'une commande, y compris celui que ce client ne connaît pas.
struct OrderStateBadge: View {
    let state: CommerceOrderState

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption)
            .foregroundStyle(tint)
    }

    private var label: String {
        switch state {
        case .awaitingPayment: return FinanceStrings.orderStateAwaitingPayment
        case .paid:            return FinanceStrings.orderStatePaid
        case .accepted:        return FinanceStrings.orderStateAccepted
        case .preparing:       return FinanceStrings.orderStatePreparing
        case .shipped:         return FinanceStrings.orderStateShipped
        case .delivered:       return FinanceStrings.orderStateDelivered
        case .cancelled:       return FinanceStrings.orderStateCancelled
        case .refunded:        return FinanceStrings.orderStateRefunded
        case .returnOpen:      return FinanceStrings.orderStateReturnOpen
        // Un état que ce client ne connaît pas se dit, il ne se traduit pas en
        // « livré » par défaut.
        case .unknown:         return FinanceStrings.orderStateUnknown
        }
    }

    private var icon: String {
        switch state {
        case .awaitingPayment: return "creditcard"
        case .paid, .accepted: return "checkmark.circle"
        case .preparing:       return "shippingbox"
        case .shipped:         return "truck.box"
        case .delivered:       return "checkmark.seal"
        case .cancelled:       return "xmark.circle"
        case .refunded:        return "arrow.uturn.left.circle"
        case .returnOpen:      return "arrow.uturn.backward"
        case .unknown:         return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch state {
        case .cancelled, .unknown: return .secondary
        case .refunded, .returnOpen: return AppColors.statusWarning
        default: return .primary
        }
    }
}

/// Ouvre un retour, un échange ou une réparation.
///
/// Distinct du litige : un retour est convenu avec le marchand, un litige
/// conteste la transaction. Les confondre ferait passer un échange de taille
/// pour une fraude.
struct ReturnRequestView: View {

    let order: CommerceOrder
    let commerce: any CommerceOrdering
    let deviceID: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var kind: CommerceReturnKind = .refund
    @State private var quantities: [String: Int] = [:]
    @State private var reasonKey = ""
    @State private var comment = ""
    @State private var phase: Phase = .composing

    private enum Phase {
        case composing
        case submitting
        case submitted(CommerceReturn)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .submitting: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing: return !reasonKey.isEmpty || !comment.isEmpty
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
                case .submitting: FinanceProgress(label: FinanceStrings.returnSubmitting)
                case .submitted:
                    FinanceMessage(icon: "checkmark.circle", text: FinanceStrings.returnSubmitted)
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.returnTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
    }

    private var draft: CommerceReturnRequest {
        CommerceReturnRequest(
            orderID: order.id,
            lines: quantities.filter { $0.value > 0 },
            kind: kind,
            reasonKey: reasonKey,
            commentText: comment.isEmpty ? nil : comment
        )
    }

    private func submit() async {
        phase = .submitting
        let submissionKey420 = await operationKeys.key(for: FinanceOperationKeys.scope("order.return", String(describing: draft)), deviceID: deviceID)
        let result = await commerce.requestReturn(
            draft, idempotency: submissionKey420
        )
        switch result {
        case .success(let opened): phase = .submitted(opened)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private var form: some View {
        Form {
            Section(FinanceStrings.returnKind) {
                Picker(FinanceStrings.returnKind, selection: $kind) {
                    Text(FinanceStrings.returnKindRefund).tag(CommerceReturnKind.refund)
                    Text(FinanceStrings.returnKindExchange).tag(CommerceReturnKind.exchange)
                    Text(FinanceStrings.returnKindRepair).tag(CommerceReturnKind.repair)
                }
                .pickerStyle(.segmented)
            }

            // Un retour partiel est le cas courant : on choisit les lignes et
            // les quantités, pas la commande entière.
            Section(FinanceStrings.returnItems) {
                ForEach(order.lines) { line in
                    Stepper(
                        value: Binding(
                            get: { quantities[line.itemID] ?? 0 },
                            set: { quantities[line.itemID] = $0 }
                        ),
                        in: 0...line.quantity
                    ) {
                        HStack {
                            Text(line.nameKey).font(.subheadline)
                            Spacer()
                            Text("\(quantities[line.itemID] ?? 0)/\(line.quantity)")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(FinanceStrings.returnReason) {
                TextField(FinanceStrings.returnReason, text: $reasonKey)
                TextField(FinanceStrings.returnComment, text: $comment, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                CustomButton(title: FinanceStrings.returnSubmit) { Task { await submit() } }
                .disabled(!draft.isSubmittable)
            }
            .financeActionRow()
        }
    }
}
