//
//  InvoiceView.swift
//  FeatureChat
//
//  Facture marchande — Bloc 6, chapitre 46.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Une facture marchande, et son règlement.
///
/// **Aucun total n'est calculé ici.** Ni le sous-total, ni les taxes, ni le
/// reste à payer : une facture est un document opposable, et deux montants qui
/// divergent d'un centime deviennent un litige.
///
/// Le document est revalidé **juste avant** le paiement. Une facture affichée
/// vieillit : elle a pu être annulée, expirer, ou être modifiée par le marchand.
struct InvoiceView: View {

    let invoiceID: String
    let invoices: any InvoiceProviding
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    /// Conversation qui porte le paiement (§5.2) — le fil, ou le dossier
    /// personnel hors conversation. Vide ⇒ le serveur choisit son dossier.
    var conversationID: String = ""
    let onDismiss: () -> Void

    /// Services de confirmation — ceux de Send Money, réutilisés (§5).
    @Environment(\.financeFlowSurface) private var surface
    @Environment(\.financeObjectReader) private var objectReader

    @State private var phase: Phase = .loading
    @State private var allocation: Allocation = .full
    @State private var partialText = ""
    @State private var idempotency: IdempotencyContext?
    @Environment(\.financeOperationKeys) private var operationKeys

    private enum Phase {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case loading
        case loaded(Invoice)
        case revalidating
        case reviewing(Invoice)
        /// La facture a changé pendant la lecture. Elle doit être relue.
        case mutated(InvoiceMutation, Invoice)
        case awaitingStepUp(Invoice, InvoiceSnapshot, PaymentAllocation)
        /// Devis du prepare (§5.2) : montant serveur, frais, total — à confirmer.
        case confirmingQuote(Invoice, TransferQuote)
        case paying
        case submitted(FinancialReference)
        case failed(String)
    }

    /// Choix d'affectation, côté interface. Traduit en `PaymentAllocation` au
    /// moment de payer, une fois le montant validé.
    private enum Allocation: Hashable {
        case full
        case partial
        case installment(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .revalidating, .paying: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .loaded, .reviewing, .awaitingStepUp: return !partialText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .reviewing(let invoice): return { phase = .loaded(invoice) }
        case .awaitingStepUp(let invoice, _, _): return { phase = .reviewing(invoice) }
        case .confirmingQuote(let invoice, _): return { phase = .reviewing(invoice) }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading:      FinanceProgress(label: FinanceStrings.invoiceLoading)
                case .revalidating: FinanceProgress(label: FinanceStrings.invoiceRevalidating)
                case .paying:       FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .loaded(let invoice): detail(invoice)
                case .reviewing(let invoice): review(invoice)
                case .mutated(let mutation, let fresh): mutated(mutation, fresh)
                case .awaitingStepUp(let invoice, let snapshot, let allocation):
                    gate(invoice, snapshot, allocation)
                case .confirmingQuote(let invoice, let quote): quoteReview(invoice, quote)
                case .submitted(let reference):
                    FinanceSubmissionView(reference: reference, onDismiss: onDismiss)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: { Task { await load() } },
                                                onDismiss: onDismiss)
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.invoiceTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    // MARK: - Chargement et règlement

    private func load() async {
        phase = .loading
        switch await invoices.invoice(id: invoiceID) {
        case .success(let invoice):
            if invoice.installments.isEmpty == false, allocation == .full,
               let next = invoice.installments.first(where: { !$0.isSettled }) {
                // Sur une facture à échéancier, la prochaine échéance est le
                // choix attendu — pas le solde entier.
                allocation = .installment(next.id)
            }
            phase = .loaded(invoice)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Revalide, puis demande l'authentification.
    ///
    /// L'ordre compte : authentifier d'abord ferait prouver son identité pour
    /// payer un document qui n'existe plus.
    private func startPayment(_ invoice: Invoice) async {
        guard case .reviewing = phase else { return }
        guard let target = resolvedAllocation(on: invoice),
              target.isWellFormed(on: invoice)
        else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }

        phase = .revalidating
        let snapshot = invoice.snapshot()
        idempotency = await operationKeys.key(for: Self.payScope(invoice, target), deviceID: deviceID)

        switch await invoices.revalidate(snapshot) {
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        case .success(let verdict):
            switch verdict {
            case .unchanged where invoices.providesQuotes:
                // Contrat §5 : prepare → devis → confirmation → execute. Le
                // montant est celui du serveur ; le devis se confirme ensuite.
                await requestQuote(invoice)
            case .unchanged:
                phase = .awaitingStepUp(invoice, snapshot, target)
            case .mutated(let mutation, let fresh):
                phase = .mutated(mutation, fresh)
            case .cancelled(let reasonKey):
                phase = .failed(reasonKey)
            case .expired:
                phase = .failed(FinanceStrings.invoiceExpired)
            }
        }
    }

    private func pay(_ invoice: Invoice, _ snapshot: InvoiceSnapshot,
                     _ target: PaymentAllocation, attestation: StepUpAttestation?) async {
        guard case .awaitingStepUp = phase else { return }
        phase = .paying
        let scope = Self.payScope(invoice, target)
        let idempotency = await operationKeys.key(for: scope, deviceID: deviceID)

        let result = await invoices.pay(
            invoiceID: invoice.id, snapshot: snapshot, allocation: target,
            idempotency: idempotency, stepUp: attestation
        )
        switch result {
        case .success(let updated):
            await operationKeys.release(scope)
            phase = .loaded(updated)
        case .failure(let error) where FinancialOutcomeRoute.isFinalityUnknown(error):
            // L'objet porte la vérité : le relire dit si le paiement est passé.
            // Afficher un échec inviterait à payer une seconde fois.
            phase = .uncertain(nil)
        case .failure(let error):   phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// `POST /invoice/prepare` : un devis, jamais un débit.
    private func requestQuote(_ invoice: Invoice) async {
        guard let idempotency else { return }
        switch await invoices.quote(invoice, conversationID: conversationID.isEmpty ? nil : conversationID,
                                    idempotency: idempotency) {
        case .success(let quote): phase = .confirmingQuote(invoice, quote)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Confirmation du devis : la soumission de Send Money — clé enregistrée,
    /// inscription avant l'execute, relecture après. L'execute part sur
    /// `/invoice/execute`, la route de l'opération préparée.
    private func confirm(_ invoice: Invoice, _ quote: TransferQuote) async {
        guard case .confirmingQuote = phase, let surface else { return }
        phase = .paying
        let outcome = await TransferSubmission.confirm(
            quote,
            recipientID: invoice.merchantID,
            counterpartyName: invoice.merchantNameKey,
            attestation: nil,
            sendMoney: surface.sendMoney,
            operationKeys: operationKeys,
            objects: objectReader,
            deviceID: deviceID
        )
        switch FinancialOutcomeRoute.route(outcome, submittedReference: quote.reference) {
        case .submitted(let reference):
            phase = .submitted(reference)
        case .needsNewAgreement:
            if case .needsNewAgreement(_, let fresh) = outcome { phase = .confirmingQuote(invoice, fresh) }
        case .verifying(let reference):
            // La facture a pu être réglée : jamais présenté comme un échec.
            phase = .uncertain(reference)
        case .failed(.expired):
            // Devis expiré : on relit la facture, rien n'est parti.
            phase = .reviewing(invoice)
        case .failed(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Portée du paiement : la facture et la répartition choisie. Refaite après
    /// un kill, la même demande retrouve la même clé.
    private static func payScope(_ invoice: Invoice, _ target: PaymentAllocation) -> String {
        FinanceOperationKeys.scope("invoice.pay", invoice.id, String(describing: target))
    }

    private func resolvedAllocation(on invoice: Invoice) -> PaymentAllocation? {
        switch allocation {
        case .full:
            return .full
        case .installment(let id):
            return .installment(id: id)
        case .partial:
            guard let decimal = Decimal(string: partialText.replacingOccurrences(of: ",", with: ".")),
                  decimal > 0 else { return nil }
            // L'exposant vient du montant dû, pas d'une constante.
            return .partial(Money(minorUnits: NSDecimalNumber(decimal: decimal).int64Value,
                                  currency: invoice.amountDue.currency))
        }
    }

    // MARK: - Vues

    private func detail(_ invoice: Invoice) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invoice.merchantNameKey).font(.headline)
                    Text(invoice.number).font(.caption.monospaced()).foregroundStyle(.secondary)
                    InvoiceStateBadge(state: invoice.state)
                }
            }

            if !invoice.lines.isEmpty {
            Section(FinanceStrings.invoiceLines) {
                ForEach(invoice.lines) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.labelKey).font(.subheadline)
                            Text("\(line.quantity) × \(money(line.unitPrice))")
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        Text(money(line.lineTotal)).font(.subheadline).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            }

            // Ventilation telle que le backend la rend. Rien n'est recomposé,
            // et ce qu'il ne rend pas ne s'affiche pas.
            Section(FinanceStrings.detailSection) {
                if let subtotal = invoice.subtotal {
                    LabeledContent(FinanceStrings.cartSubtotal, value: money(subtotal))
                }
                if let discount = invoice.discountTotal {
                    LabeledContent(FinanceStrings.invoiceDiscount, value: money(discount))
                }
                if let tax = invoice.taxTotal {
                    LabeledContent(FinanceStrings.cartTax, value: money(tax))
                }
                if let total = invoice.total {
                    LabeledContent(FinanceStrings.total, value: money(total))
                }
                if invoice.paidAmount.minorUnits > 0 {
                    LabeledContent(FinanceStrings.invoicePaid, value: money(invoice.paidAmount))
                }
                LabeledContent(FinanceStrings.invoiceAmountDue) {
                    Text(money(invoice.amountDue)).font(.body.weight(.semibold)).monospacedDigit()
                }
            }

            if !invoice.installments.isEmpty {
                Section(FinanceStrings.creditSchedule) {
                    ForEach(invoice.installments) { instalment in
                        HStack {
                            Text("#\(instalment.number)")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(money(instalment.amount)).monospacedDigit()
                                Text(instalment.dueAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if instalment.isSettled {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if invoice.isPayable() {
                paymentSection(invoice)
            } else {
                Section {
                    Label(FinanceStrings.invoiceNotPayable, systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func paymentSection(_ invoice: Invoice) -> some View {
        Section(FinanceStrings.invoicePayTitle) {
            Picker(FinanceStrings.invoicePayTitle, selection: $allocation) {
                Text(FinanceStrings.invoicePayFull).tag(Allocation.full)
                if invoice.allowsPartialPayment {
                    Text(FinanceStrings.invoicePayPartial).tag(Allocation.partial)
                }
                ForEach(invoice.installments.filter { !$0.isSettled }) { instalment in
                    Text(String(format: FinanceStrings.invoicePayInstallment, instalment.number))
                        .tag(Allocation.installment(instalment.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            if allocation == .partial {
                HStack {
                    TextField("0", text: $partialText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.amount)
                    Text(invoice.amountDue.currency.code).foregroundStyle(.secondary)
                }
            }

            CustomButton(title: FinanceStrings.flowReview) { phase = .reviewing(invoice) }
            .disabled(resolvedAllocation(on: invoice)?.isWellFormed(on: invoice) != true)
        }

        if invoice.allowsMultiplePayers {
            Section {
                Text(FinanceStrings.invoiceMultiplePayers).font(.caption)
            }
        }
    }

    /// La facture a changé. **Aucun paiement ne suit automatiquement.**
    ///
    /// Le cas grave est nommé séparément : un contenu modifié à version
    /// constante est une altération que le marchand n'a pas déclarée.
    private func mutated(_ mutation: InvoiceMutation, _ fresh: Invoice) -> some View {
        VStack(spacing: 14) {
            Image(systemName: mutation == .silentContentChange
                  ? "exclamationmark.shield.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(mutation == .silentContentChange ? AppColors.statusDanger : AppColors.statusWarning)

            Text(FinanceStrings.invoiceChangedTitle).font(.headline)
            Text(FinanceStrings.invoiceMutationReason(mutation))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)

            // Une modification silencieuse ne se « relit » pas : on ne propose
            // pas de continuer sur un document dont le marchand a masqué le
            // changement.
            if mutation != .silentContentChange {
                Button(FinanceStrings.invoiceReview) { phase = .loaded(fresh) }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(.top, 48)
        .accessibilityElement(children: .combine)
    }

    private func review(_ invoice: Invoice) -> some View {
        FinancePage {
            Text(FinanceStrings.invoiceReview).font(.title2.bold())
            LabeledContent(FinanceStrings.receiptReference, value: invoice.id)
            if let amount = resolvedAllocation(on: invoice)?.displayedAmount(on: invoice) {
                LabeledContent(FinanceStrings.amount, value: money(amount))
            }
        } actions: {
            CustomButton(title: FinanceStrings.invoicePay) { Task { await startPayment(invoice) } }
        }
    }

    private func gate(_ invoice: Invoice, _ snapshot: InvoiceSnapshot,
                      _ target: PaymentAllocation) -> some View {
        StepUpGate(
            authenticator: stepUp,
            requiredLevel: .biometric,
            reason: FinanceStrings.stepUpReasonInvoice,
            correlationID: idempotency?.correlationID ?? CorrelationId(),
            deviceID: deviceID,
            onSatisfied: { attestation in
                Task { await pay(invoice, snapshot, target, attestation: attestation) }
            },
            onCancel: { phase = .reviewing(invoice) }
        )
    }

    private func quoteReview(_ invoice: Invoice, _ quote: TransferQuote) -> some View {
        QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
            VStack(spacing: 0) {
                QuoteValidityBanner(validity: validity) {
                    Task { await requestQuote(invoice) }
                }
                FinanceReviewSummary(
                    title: FinanceStrings.flowReviewTitle,
                    amount: AmountEntry.format(quote.totalAmount ?? quote.amount,
                                               quote.totalCurrency ?? quote.currency),
                    amountCaption: invoice.merchantNameKey,
                    rows: Self.quoteRows(invoice, quote)
                ) {
                    Text(FinanceStrings.sendQuoteLimited)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                }
                CustomButton(title: FinanceStrings.sendConfirm,
                             icon: "arrow.up.right", iconPosition: .trailing) {
                    Task { await confirm(invoice, quote) }
                }
                .disabled(!validity.allowsConfirmation)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(AppColors.walletCanvas)
        }
    }

    private static func quoteRows(_ invoice: Invoice, _ quote: TransferQuote) -> [FinanceReviewSummary<Text>.Row] {
        var rows: [FinanceReviewSummary<Text>.Row] = [
            .init(FinanceStrings.receiptReference, invoice.number),
            .init(FinanceStrings.amount, AmountEntry.format(quote.amount, quote.currency)),
        ]
        if let fee = quote.feeAmount {
            rows.append(.init(FinanceStrings.fees, AmountEntry.format(fee, quote.feeCurrency ?? quote.currency)))
        }
        if let total = quote.totalAmount {
            rows.append(.init(FinanceStrings.total,
                              AmountEntry.format(total, quote.totalCurrency ?? quote.currency),
                              isProminent: true))
        }
        return rows
    }

    private func money(_ value: Money) -> String {
        AmountEntry.format(value.majorUnitsForDisplay, value.currency.code)
    }
}

/// L'état d'une facture, y compris celui que ce client ne connaît pas.
struct InvoiceStateBadge: View {
    let state: InvoiceState

    var body: some View {
        Label(label, systemImage: icon).font(.caption).foregroundStyle(tint)
    }

    private var label: String {
        switch state {
        case .draft:         return FinanceStrings.invoiceStateDraft
        case .issued:        return FinanceStrings.invoiceStateIssued
        case .viewed:        return FinanceStrings.invoiceStateViewed
        case .partiallyPaid: return FinanceStrings.invoiceStatePartiallyPaid
        case .paid:          return FinanceStrings.invoiceStatePaid
        case .cancelled:     return FinanceStrings.invoiceStateCancelled
        case .expired:       return FinanceStrings.invoiceStateExpired
        case .disputed:      return FinanceStrings.invoiceStateDisputed
        case .unknown:       return FinanceStrings.invoiceStateUnknown
        }
    }

    private var icon: String {
        switch state {
        case .draft:                     return "doc"
        case .issued, .viewed:           return "doc.text"
        case .partiallyPaid:             return "circle.lefthalf.filled"
        case .paid:                      return "checkmark.seal"
        case .cancelled, .expired:       return "xmark.circle"
        case .disputed:                  return "exclamationmark.bubble"
        case .unknown:                   return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch state {
        case .paid:                          return AppColors.statusSuccess
        case .cancelled, .expired, .unknown: return .secondary
        case .disputed, .partiallyPaid:      return AppColors.statusWarning
        default:                             return .primary
        }
    }
}
