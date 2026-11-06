//
//  QRPaymentView.swift
//  FeatureChat
//
//  Paiement d'un QR résolu — Bloc 3, chapitre 22, étapes 10 à 12.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Fait chiffrer puis exécute le paiement d'un QR **déjà résolu**.
///
/// Le QR n'entre jamais ici sous forme brute : cette vue reçoit un
/// `ResolvedQR`, c'est-à-dire l'identité, le montant et les actions que le
/// backend a établis. Elle refait ensuite le chemin ordinaire — devis, aperçu,
/// divergence, permis — parce qu'un paiement par QR n'a aucune raison d'être
/// moins vérifié qu'un envoi saisi à la main.
struct QRPaymentView: View {

    let resolved: ResolvedQR
    let quoting: any TransferQuoting
    let sendMoney: SendMoneyUseCase
    let stepUp: any StepUpAuthenticating
    let conversationID: String
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .quoting
    @Environment(\.financeObjectReader) private var objectReader
    @Environment(\.financeOperationKeys) private var operationKeys
    @State private var amountText: String = ""

    private enum Phase: Equatable {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        /// QR statique : le payeur saisit le montant.
        case enteringAmount
        case quoting
        case reviewing(TransferQuote)
        case steppingUp(TransferQuote)
        case submitting
        case conditionsChanged(TransferQuote, [DecisionField])
        case done(FinancialReference)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .quoting, .submitting: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .reviewing, .steppingUp, .conditionsChanged: return !amountText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .reviewing, .conditionsChanged: return resolved.amount == nil ? { phase = .enteringAmount } : nil
        case .steppingUp(let quote): return { phase = .reviewing(quote) }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .enteringAmount:        amountEntry
                case .quoting:               progress(FinanceStrings.sendQuoting)
                case .reviewing(let q):      review(q, changed: [])
                case .steppingUp(let q):     stepUpGate(for: q)
                case .submitting:            progress(FinanceStrings.sendSubmitting)
                case .conditionsChanged(let q, let f): review(q, changed: f)
                case .done(let reference): FinanceSubmissionView(reference: reference, onDismiss: onDismiss)
                case .failed(let m):         message("exclamationmark.triangle", m)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference, onCheckAgain: nil, onDismiss: onDismiss)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.qrTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, discardDetail: .moneyEntry, onClose: onDismiss)
        }
        .financeLoadOnce { await start() }
    }

    // MARK: - Étapes

    private func start() async {
        // Un QR dynamique porte son montant ; un QR statique laisse le payeur
        // le choisir. La distinction vient du backend, pas de la charge.
        if let amount = resolved.amount {
            amountText = "\(amount)"
            await requestQuote()
        } else {
            phase = .enteringAmount
        }
    }

    private func requestQuote() async {
        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }
        phase = .quoting

        let draft = TransferDraft(
            recipientID: resolved.counterparty.actorID,
            amount: amount,
            currency: resolved.currency ?? "BIF",
            conversationID: conversationID
        )

        switch await quoting.quote(for: draft) {
        case .success(let quote): phase = .reviewing(quote)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func confirm(_ quote: TransferQuote, attestation: StepUpAttestation?) async {
        switch phase {
        case .reviewing, .conditionsChanged, .steppingUp: break
        default: return
        }
        phase = .submitting

        // Clé enregistrée et inscription avant soumission : voir `TransferSubmission`.
        let outcome = await TransferSubmission.confirm(
            quote,
            recipientID: resolved.counterparty.actorID,
            counterpartyName: resolved.counterparty.displayName,
            attestation: attestation,
            sendMoney: sendMoney,
            operationKeys: operationKeys,
            objects: objectReader,
            deviceID: deviceID
        )

        switch FinancialOutcomeRoute.route(outcome, submittedReference: quote.reference) {
        case .submitted(let reference):
            phase = .done(reference)
        case .needsNewAgreement:
            if case .needsNewAgreement(let fields, let fresh) = outcome {
                phase = .conditionsChanged(fresh, fields)
            }
        case .verifying(let reference):
            // Le marchand a peut-être été payé : ni échec affiché, ni objet perdu.
            // Déjà inscrit avant soumission, et relu : la réconciliation tranchera.
            phase = .uncertain(reference)
        case .failed(.expired):
            // Expiré pendant l'authentification ou la confirmation : rien n'est
            // parti, on redemande un devis plutôt que d'afficher un échec.
            await requestQuote()
        case .failed(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func progress(_ label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func message(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var amountEntry: some View {
        Form {
            Section { counterparty }
            Section(FinanceStrings.amount) {
                HStack {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.amount)
                    Text(resolved.currency ?? "BIF").foregroundStyle(.secondary)
                }
            }
            Section {
                CustomButton(title: FinanceStrings.sendContinue) {
                    Task { await requestQuote() }
                }
            }
            .financeActionRow()
        }
    }

    private var counterparty: some View {
        HStack(spacing: 12) {
            Image(systemName: resolved.kind == .merchant ? "storefront" : "person.crop.circle")
                .font(.system(size: 34)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(resolved.counterparty.displayName).font(.body.weight(.medium))
                    if resolved.counterparty.verification.showsTrustBadge {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(.blue)
                    }
                }
                if resolved.requiresQuarantineWarning {
                    Text(FinanceStrings.qrQuarantine)
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func review(_ quote: TransferQuote, changed: [DecisionField]) -> some View {
        QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
        Form {
            if validity != .valid {
                Section {
                    QuoteValidityBanner(validity: validity) { Task { await requestQuote() } }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if !changed.isEmpty {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FinanceStrings.termsChangedTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(FinanceStrings.termsChangedDetail(
                                changed.map { FinanceStrings.decisionFieldName($0.rawValue) }
                            ))
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppColors.statusWarning)
                    }
                }
            }

            Section { counterparty }

            Section(FinanceStrings.detailSection) {
                LabeledContent(FinanceStrings.amount,
                               value: AmountEntry.format(quote.amount, quote.currency))
                if let fee = quote.feeAmount {
                    LabeledContent(FinanceStrings.fees,
                                   value: AmountEntry.format(fee, quote.feeCurrency ?? quote.currency))
                }
                if let total = quote.totalAmount {
                    LabeledContent(FinanceStrings.total,
                                   value: AmountEntry.format(total, quote.totalCurrency ?? quote.currency))
                }
            }

            Section {
                CustomButton(title: changed.isEmpty
                         ? FinanceStrings.sendConfirm
                         : FinanceStrings.sendAcceptNewTerms) {
                    // Le step-up passe avant l'exécution. Le niveau vient du
                    // backend ; `.biometric` est le plancher retenu pour un
                    // paiement scanné, jamais `.none`.
                    phase = .steppingUp(quote)
                }
                .disabled(!validity.allowsConfirmation)
            } footer: {
                Text(FinanceStrings.sendQuoteLimited).font(.caption)
            }
        }
        }
    }

    private func stepUpGate(for quote: TransferQuote) -> some View {
        StepUpGate(
            authenticator: stepUp,
            requiredLevel: .biometric,
            reason: FinanceStrings.stepUpReasonPayment,
            correlationID: quote.reference.correlationID,
            deviceID: deviceID,
            onSatisfied: { attestation in
                Task { await confirm(quote, attestation: attestation) }
            },
            onCancel: {
                // Annuler le step-up ramène au récapitulatif, pas à zéro :
                // l'utilisateur n'a rien invalidé, il a seulement refusé un geste.
                phase = .reviewing(quote)
            }
        )
    }
}
