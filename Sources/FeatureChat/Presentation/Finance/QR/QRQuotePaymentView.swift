//
//  QRQuotePaymentView.swift
//  FeatureChat
//
//  Payer un code scanné, par le devis du serveur — §5.2.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Le code lu part **tel quel** à `POST /qr/prepare`, qui le résout (marchand,
/// montant) et rend un devis ; l'utilisateur confirme, puis `/qr/execute`.
///
/// C'est la réponse du backend (Q15) : `/qr/parse` ne fait que valider la
/// charge, c'est `prepare` qui résout. L'écran n'invente donc ni marchand ni
/// montant — il montre ce que le devis du serveur dit.
struct QRQuotePaymentView: View {

    let payload: String
    let resolver: any QRResolving
    let deviceID: String
    /// Le fil, ou le dossier personnel hors conversation (§5.1.1).
    var conversationID: String = ""
    let onDismiss: () -> Void

    @Environment(\.financeFlowSurface) private var surface
    @Environment(\.financeObjectReader) private var objectReader
    @Environment(\.financeOperationKeys) private var operationKeys

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case reviewing(TransferQuote)
        case paying
        case submitted(FinancialReference)
        /// Issue inconnue après soumission : **jamais un échec**.
        case uncertain(FinancialReference?)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .loading, .paying: return true
        default: return false
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading:  FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .paying:   FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .reviewing(let quote): review(quote)
                case .submitted(let reference):
                    FinanceSubmissionView(reference: reference, onDismiss: onDismiss)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: { Task { await requestQuote() } },
                                                onDismiss: onDismiss)
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.qrTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: false, back: nil, onClose: onDismiss)
        }
        .financeLoadOnce { await requestQuote() }
    }

    // MARK: - Devis

    /// Une clé par code lu : relu, le même code rend le même devis.
    private func requestQuote() async {
        phase = .loading
        let key = await operationKeys.key(for: FinanceOperationKeys.scope("qr.pay", payload), deviceID: deviceID)
        switch await resolver.quotePayment(payload: payload,
                                           conversationID: conversationID.isEmpty ? nil : conversationID,
                                           idempotency: key) {
        case .success(let quote): phase = .reviewing(quote)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// La soumission partagée de Send Money : clé enregistrée, inscription avant
    /// l'execute, relecture après. L'execute part sur `/qr/execute`.
    private func confirm(_ quote: TransferQuote) async {
        guard case .reviewing = phase, let surface else { return }
        phase = .paying
        let outcome = await TransferSubmission.confirm(
            quote,
            recipientID: quote.reference.id,
            counterpartyName: nil,
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
            if case .needsNewAgreement(_, let fresh) = outcome { phase = .reviewing(fresh) }
        case .verifying(let reference):
            // L'argent est peut-être parti : jamais présenté comme un échec.
            phase = .uncertain(reference)
        case .failed(.expired):
            // Devis expiré : rien n'est parti, un nouveau devis.
            await requestQuote()
        case .failed(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Revue

    private func review(_ quote: TransferQuote) -> some View {
        QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
            VStack(spacing: 0) {
                QuoteValidityBanner(validity: validity) { Task { await requestQuote() } }
                FinanceReviewSummary(
                    title: FinanceStrings.flowReviewTitle,
                    amount: AmountEntry.format(quote.totalAmount ?? quote.amount,
                                               quote.totalCurrency ?? quote.currency),
                    amountCaption: nil,
                    rows: Self.rows(quote)
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

    private static func rows(_ quote: TransferQuote) -> [FinanceReviewSummary<Text>.Row] {
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
