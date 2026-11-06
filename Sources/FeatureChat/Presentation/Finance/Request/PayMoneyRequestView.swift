//
//  PayMoneyRequestView.swift
//  FeatureChat
//
//  Payer une demande reçue — INTEGRATION_CHAT_FINANCE.md §4 et §4.1.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Paie une demande d'argent reçue.
///
/// « Ouvre un Send Money (quote + fingerprint). Pas un débit magique. » (§4)
/// `POST /request-money/pay` rend un devis ; il se relit ici comme celui d'un
/// envoi, se confirme explicitement, puis part par le même execute — une seule
/// fois, jamais rejoué. Le paiement est ensuite publié dans la conversation.
///
/// Demande à montant libre (`FREE`) : le payeur saisit d'abord le montant.
struct PayMoneyRequestView: View {

    let request: MoneyRequestOverlay
    let conversationID: String
    let onDismiss: () -> Void

    @Environment(\.financeFlowSurface) private var surface
    @Environment(\.financeObjectReader) private var objectReader
    @Environment(\.financeOperationKeys) private var operationKeys

    @State private var phase: Phase = .preparing
    @State private var amountText = ""
    /// Une seule reprise après déverrouillage — voir `FinanceConfirmRetry`.
    @State private var retriedAfterUnlock = false
    /// Le dernier échec vient d'une session verrouillée.
    @State private var failedLocked = false

    private enum Phase: Equatable {
        case enteringAmount
        case preparing
        case reviewing(TransferQuote)
        case submitting
        case done(FinancialReference)
        case verifying(FinancialReference)
        case failed(String)
    }

    var body: some View {
        FinanceNavigationScope {
            content
                .navigationTitle(FinanceStrings.requestPayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(FinanceStrings.close, action: onDismiss)
                            .disabled(phase == .submitting)
                    }
                }
        }
        .interactiveDismissDisabled(phase == .submitting)
        .task {
            guard phase == .preparing else { return }
            if request.amountMode == .free { phase = .enteringAmount } else { await prepare(amount: nil) }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .enteringAmount:
            amountEntry
        case .preparing:
            FinanceProgress(label: FinanceStrings.requestPayPreparing)
        case .reviewing(let quote):
            review(quote)
        case .submitting:
            FinanceProgress(label: FinanceStrings.sendSubmitting)
        case .done(let reference):
            FinanceSubmissionView(reference: reference, onDismiss: onDismiss)
        case .verifying(let reference):
            FinanceSubmissionView(reference: reference,
                                  title: FinanceStrings.sendVerifyingTitle,
                                  detail: FinanceStrings.errorMessage(.timeoutUnknown),
                                  animation: .verifying,
                                  onDismiss: onDismiss)
        case .failed(let message):
            // Issue tranchée (refus ou échec avant envoi) : l'incertain passe
            // par `.verifying`. Réessayer relance `/pay` — un nouveau devis et
            // une nouvelle empreinte, ce que le contrat demande après un
            // refus d'empreinte (`CF_021`, « prepare again »).
            FinanceFailureView(
                title: FinanceStrings.failurePaymentTitle,
                message: message,
                locked: failedLocked,
                onRetry: {
                    retriedAfterUnlock = false
                    Task { await prepare(amount: request.amountMode == .free ? enteredAmount : nil) }
                },
                onDismiss: onDismiss
            )
        }
    }

    // MARK: - Étapes

    private func prepare(amount: Decimal?) async {
        guard let responder = surface?.requestResponder else {
            phase = .failed(FinanceStrings.errorMessage(.capabilityUnavailable))
            return
        }
        phase = .preparing
        switch await responder.pay(request.reference, conversationID: conversationID,
                                   amount: amount, currency: request.currency) {
        case .success(let quote):  phase = .reviewing(quote)
        case .failure(let error):  phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func confirm(_ quote: TransferQuote) async {
        guard case .reviewing = phase, let surface else { return }
        phase = .submitting

        // Même soumission qu'un envoi : clé enregistrée, inscription avant
        // l'execute, relecture après. `recipientID` n'y sert qu'à comparer le
        // devis accepté au devis relu — la référence de la demande suffit.
        let outcome = await TransferSubmission.confirm(
            quote,
            recipientID: request.reference.id,
            counterpartyName: nil,
            attestation: nil,
            sendMoney: surface.sendMoney,
            operationKeys: operationKeys,
            objects: objectReader,
            deviceID: surface.deviceID
        )

        switch FinancialOutcomeRoute.route(outcome, submittedReference: quote.reference) {
        case .submitted(let reference):
            phase = .done(reference)
            await requestChanged()
        case .needsNewAgreement:
            // Les conditions ont bougé : montrer le nouveau devis, pas repartir.
            if case .needsNewAgreement(_, let fresh) = outcome { phase = .reviewing(fresh) }
        case .verifying(let reference):
            // L'argent est peut-être parti : jamais présenté comme un échec.
            phase = .verifying(reference)
            await requestChanged()
        case .failed(.expired):
            await prepare(amount: request.amountMode == .free ? enteredAmount : nil)
        case .failed(let error):
            if !retriedAfterUnlock,
               await FinanceConfirmRetry.sessionNowAllowsConfirm(after: error, session: surface.financeSession) {
                retriedAfterUnlock = true
                phase = .reviewing(quote)
                await confirm(quote)
                return
            }
            if case .capabilityUnavailable = error { failedLocked = true } else { failedLocked = false }
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// La demande a changé : c'est **sa** bulle qui le dit, pas une nouvelle.
    ///
    /// Le paiement n'est pas publié comme un message à part — il apparaissait
    /// comme un « Argent envoyé » de plus, pendant que la demande gardait
    /// « Payer ». La demande est relue au serveur (sa part passe à
    /// `PAYMENT_SUBMITTED`), et sa carte, prévenue, masque ses boutons.
    private func requestChanged() async {
        // La part vient de changer côté serveur : aucune lecture d'avant le
        // paiement ne doit être resservie.
        await surface?.requestResponder?.forget(request.reference)
        _ = await objectReader?.refresh(request.reference)
        NotificationCenter.default.post(name: .financeRequestDidChange, object: request.reference.id)
    }

    // MARK: - Présentation

    private var enteredAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var amountEntry: some View {
        FinancePage {
            Text(FinanceStrings.requestPayAmountHint)
                .font(.subheadline)
                .foregroundStyle(AppColors.subtitleGray)
            TextField("0", text: $amountText)
                .keyboardType(.decimalPad)
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
        } actions: {
            CustomButton(title: FinanceStrings.requestPayContinue) {
                Task { await prepare(amount: enteredAmount) }
            }
            .disabled((enteredAmount ?? 0) <= 0)
        }
    }

    private func review(_ quote: TransferQuote) -> some View {
        QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
            VStack(spacing: 0) {
                QuoteValidityBanner(validity: validity) {
                    Task { await prepare(amount: request.amountMode == .free ? enteredAmount : nil) }
                }
                FinanceReviewSummary(
                    title: FinanceStrings.flowReviewTitle,
                    amount: AmountEntry.format(quote.totalAmount ?? quote.amount,
                                               quote.totalCurrency ?? quote.currency),
                    amountCaption: FinanceStrings.requestCardReceivedTitle,
                    rows: rows(quote)
                ) {
                    Text(FinanceStrings.sendQuoteLimited)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                }
                CustomButton(title: FinanceStrings.sendConfirm,
                             icon: "arrow.up.right", iconPosition: .trailing) {
                    Task { await confirm(quote) }
                }
                .disabled(!validity.allowsConfirmation)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(AppColors.walletCanvas)
        }
    }

    private func rows(_ quote: TransferQuote) -> [FinanceReviewSummary<Text>.Row] {
        var rows: [FinanceReviewSummary<Text>.Row] = [
            .init(FinanceStrings.amount, AmountEntry.format(quote.amount, quote.currency))
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
}
