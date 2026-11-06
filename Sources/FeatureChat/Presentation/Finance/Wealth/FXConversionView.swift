//
//  FXConversionView.swift
//  FeatureChat
//
//  Conversion de devises — Bloc 5, chapitre 37.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Convertit entre portefeuilles.
///
/// **Aucun calcul ici.** Le montant converti, les frais et le total viennent du
/// devis. Un `amount * rate` dans cette vue produirait un chiffre qui ne
/// correspondrait à aucun débit réel — et la gate §28 le refuserait en CI.
struct FXConversionView: View {

    let fx: any FXConverting
    let deviceID: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .loadingWallets
    @State private var wallets: [CurrencyWallet] = []
    @State private var source: CurrencyWallet?
    @State private var targetCurrency: String = ""
    @State private var amountText = ""
    @State private var showsRules = false
    @Environment(\.financeOperationKeys) private var operationKeys

    private enum Phase: Equatable {
        case loadingWallets
        case noWallet
        case composing
        case quoting
        case reviewing(FinancialQuote)
        case converting
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain
        case done(FinancialReference)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .quoting, .converting: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing, .reviewing: return !amountText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .reviewing: return { phase = .composing }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loadingWallets:   FinanceProgress(label: FinanceStrings.hubLoading)
                case .noWallet:         FinanceMessage(icon: "wallet.pass", text: FinanceStrings.fxNoWallet)
                case .composing:        composer
                case .quoting:          FinanceProgress(label: FinanceStrings.sendQuoting)
                case .reviewing(let q): review(q)
                case .converting:       FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .done(let reference): FinanceSubmissionView(reference: reference, onDismiss: onDismiss)
                case .uncertain:
                    FinanceUncertainOutcomeView(reference: nil, onCheckAgain: nil, onDismiss: onDismiss)
                case .failed(let m):    FinanceMessage(icon: "exclamationmark.triangle", text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.fxTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, discardDetail: .moneyEntry, onClose: onDismiss)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsRules = true } label: {
                        Label(FinanceStrings.fxRulesTitle, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .financeDestination(isPresented: $showsRules) {
            FXAutomaticRulesView(
                fx: fx, deviceID: deviceID,
                onDismiss: { showsRules = false }
            )
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await fx.wallets() {
        case .success(let list):
            wallets = list
            source = list.first(where: \.isPrimary) ?? list.first
            targetCurrency = list.first(where: { $0.currency != source?.currency })?.currency ?? ""
            phase = list.isEmpty ? .noWallet : .composing
        case .failure(let e):
            phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func requestQuote() async {
        guard let source, !targetCurrency.isEmpty,
              let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }
        phase = .quoting

        switch await fx.quote(from: source.currency, to: targetCurrency, sourceAmount: amount) {
        case .success(let quote): phase = .reviewing(quote)
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private func convert(_ quote: FinancialQuote) async {
        guard case .reviewing = phase else { return }
        phase = .converting
        // Clé tirée du devis, persistée : fermer et rouvrir l'écran sur le même
        // devis la retrouve.
        let scope = FinanceOperationKeys.scope("fx.convert", quote.quoteID, quote.quoteVersion)
        let idempotency = await operationKeys.key(for: scope, deviceID: deviceID)
        switch await fx.convert(quote: quote, idempotency: idempotency) {
        case .success(let conversion):
            await operationKeys.release(scope)
            phase = .done(conversion.reference)
        case .failure(let e) where FinancialOutcomeRoute.isFinalityUnknown(e):
            // La conversion a peut-être eu lieu. Afficher un échec inviterait à
            // convertir une seconde fois.
            phase = .uncertain
        case .failure(let e): phase = .failed(FinanceStrings.errorMessage(e))
        }
    }

    private var composer: some View {
        Form {
            Section(FinanceStrings.fxFrom) {
                Picker(FinanceStrings.fxFrom, selection: $source) {
                    ForEach(wallets, id: \.id) { wallet in
                        Text("\(wallet.currency) — \(wallet.available.majorUnitsForDisplay)")
                            .tag(Optional(wallet))
                    }
                }
                // Un solde daté est signalé, pas masqué : l'utilisateur doit
                // savoir qu'il décide sur une valeur qui a pu bouger.
                if let source, source.isStale() {
                    Label(FinanceStrings.fxStaleBalance, systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }

            Section(FinanceStrings.fxTo) {
                Picker(FinanceStrings.fxTo, selection: $targetCurrency) {
                    ForEach(wallets.filter { $0.currency != source?.currency }, id: \.id) { wallet in
                        Text(wallet.currency).tag(wallet.currency)
                    }
                }
            }

            Section(FinanceStrings.amount) {
                HStack {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.amount)
                    Text(source?.currency ?? "").foregroundStyle(.secondary)
                }
            }

            Section {
                CustomButton(title: FinanceStrings.sendContinue) { Task { await requestQuote() } }
                .disabled(source == nil || targetCurrency.isEmpty)
            }
            .financeActionRow()
        }
    }

    /// Réévaluée chaque seconde : un taux affiché puis laissé ouvert expirait
    /// sans que le bouton se désactive — Bloc 10, chapitre 80.
    private func review(_ quote: FinancialQuote) -> some View {
        QuoteValidityReader(expiresAt: quote.validUntil) { validity in
            FinancePage {
                Text(FinanceStrings.flowReview).font(.largeTitle.bold())
                QuoteValidityBanner(validity: validity) { Task { await requestQuote() } }
                FinanceQuoteSummary(quote: quote)
            } actions: {
                CustomButton(title: FinanceStrings.fxConvert) { Task { await convert(quote) } }
                    .disabled(!validity.allowsConfirmation || !quote.isExecutable() || !quote.isIntact)
            }
        }
    }
}
