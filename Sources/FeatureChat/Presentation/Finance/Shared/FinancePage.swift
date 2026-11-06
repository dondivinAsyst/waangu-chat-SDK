import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Shared page layout for finance tasks. Buttons, cards and typography continue
/// to use SharedUI; this component only owns scrolling and the bottom action area.
struct FinancePage<Content: View, Actions: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.spacingL, content: content)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(DesignTokens.spacingL)
        }
        .scrollDismissesKeyboard(.interactively)
        // Fond neutre, comme les écrans refaits.
        //
        // C'était `backgroundGradient.opacity(0.4)`, un bleuté pâle : les seize
        // écrans qui passent par ce conteneur avaient donc un fond différent de
        // ceux refaits sur `walletCanvas`, et la surface financière changeait de
        // couleur d'un parcours à l'autre.
        .background(AppColors.walletCanvas)
        .foregroundStyle(AppColors.textPrimary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: DesignTokens.spacingS, content: actions)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(DesignTokens.spacingM)
                // Barre d'action posée sur le même fond, séparée par un filet
                // plutôt que par un aplat blanc : l'aplat faisait paraître le
                // bouton enfermé dans une carte.
                .background(alignment: .top) {
                    VStack(spacing: 0) {
                        AppColors.separator.frame(height: 0.33)
                        AppColors.walletCanvas
                    }
                }
        }
        .tint(AppColors.primary)
    }
}

/// Shared submitted-result page. A reference alone never establishes settlement.
struct FinanceSubmissionView: View {
    let reference: FinancialReference
    /// Motif saisi par l'émetteur, publié avec la carte. `nil` : rien à dire.
    var note: String?
    var title: String = FinanceStrings.sendDone
    var detail: String = FinanceStrings.flowSubmittedDetail
    /// Transmis par défaut ; `.verifying` quand l'issue est inconnue.
    var animation: FinanceStatusAnimationKind = .submitted
    let onDismiss: () -> Void
    @Environment(\.financeFlowSurface) private var surface
    @State private var showsSupport = false
    @Environment(\.financePublishReference) private var publishReference
    @State private var isPublishing = false
    @State private var attemptedPublication = false
    private var publicationPending: Bool { isPublishing || (publishReference != nil && !attemptedPublication) }
    @State private var publicationFailed = false
    @Environment(\.financeObjectReader) private var reader
    @State private var payload: FinancialCardPayload?
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var showsDetails = false

    var body: some View {
        FinancePage {
            if let payload {
                FinancialObjectSummary(payload: payload)
            } else {
                FinanceStatusAnimation(animation)
                    .frame(width: 112, height: 112)
                    .frame(maxWidth: .infinity).padding(.top, DesignTokens.spacingL)
                Text(title).font(.title.bold()).frame(maxWidth: .infinity)
                Text(detail).font(.body).foregroundStyle(AppColors.subtitleGray)
            }
            VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
                Text(FinanceStrings.receiptReference).font(.caption).foregroundStyle(AppColors.subtitleGray)
                Text(reference.id).font(.body.monospaced()).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(DesignTokens.spacingM).cardStyle()
            if isPublishing { ProgressView() }
            if let refreshError { Text(refreshError).font(.footnote).foregroundStyle(.secondary) }
            if reader != nil {
                Button { Task { await refresh() } } label: {
                    Label(FinanceStrings.flowCheckStatus, systemImage: "arrow.clockwise")
                }.disabled(isRefreshing)
            }
            if payload != nil, surface != nil {
                Button { showsDetails = true } label: {
                    Label(FinanceStrings.detailSection, systemImage: "doc.text.magnifyingglass")
                }
            }
            if publicationFailed {
                Text(FinanceStrings.flowBubbleFailed).foregroundStyle(.secondary)
                Button(FinanceStrings.flowShareInChat) { Task { await publish() } }
            }
            if surface != nil {
                Button { showsSupport = true } label: {
                    Label(FinanceStrings.actionsSupport, systemImage: "lifepreserver")
                }
            }
        } actions: {
            CustomButton(title: FinanceStrings.flowReturn, icon: "bubble.left", action: onDismiss)
                .disabled(publicationPending)
        }
        .preference(key: FinanceActivityBusyKey.self, value: publicationPending)
        .financeLoadOnce {
            await publish()
            if let reader { payload = await reader.current(for: reference) }
        }
        .financeDestination(isPresented: $showsDetails) {
            if let payload, let surface {
                FinancialObjectActionsView(payload: payload, surface: surface,
                                           conversationID: nil, onDismiss: { showsDetails = false })
                    .environment(\.financePublishReference, nil)
            }
        }
        .financeDestination(isPresented: $showsSupport) {
            if let surface {
                SupportCaseView(reference: reference, support: surface.support, deviceID: surface.deviceID,
                                onDismiss: { showsSupport = false })
                    .environment(\.financePublishReference, nil)
            }
        }
    }
    @MainActor
    private func publish() async {
        guard let publishReference, !isPublishing else { return }
        isPublishing = true
        publicationFailed = !(await publishReference(reference, note))
        isPublishing = false
        attemptedPublication = true
    }

    @MainActor
    private func refresh() async {
        guard let reader, !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        switch await reader.refresh(reference) {
        case .success(let current): payload = current
        case .failure(let error): refreshError = FinanceStrings.errorMessage(error)
        }
        isRefreshing = false
    }

}


/// The amount treatment extracted from Send Money, shared by product reviews.
/// Callers provide the existing formatted value; this view performs no money arithmetic.
struct FinanceAmountSummary: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingS) {
            Text(title).font(.subheadline)
            Text(value).font(.largeTitle.weight(.semibold)).monospacedDigit()
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(AppColors.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.spacingL)
        .background(AppColors.amountWellBackground,
                    in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusDefault))
        .accessibilityElement(children: .combine)
    }
}

/// One rendering of the existing quote fields for FX and international transfers.
struct FinanceQuoteSummary: View {
    let quote: FinancialQuote

    var body: some View {
        VStack(spacing: DesignTokens.spacingL) {
            FinanceAmountSummary(title: FinanceStrings.amount,
                                 value: AmountEntry.format(quote.sourceAmount, quote.sourceCurrency))
            Image(systemName: "arrow.down").foregroundStyle(AppColors.primary)
            FinanceAmountSummary(title: FinanceStrings.remittanceReceives,
                                 value: AmountEntry.format(quote.targetAmount, quote.targetCurrency))
            VStack(spacing: DesignTokens.spacingM) {
                LabeledContent(FinanceStrings.fxRate, value: "\(quote.exchangeRate)")
                if let reference = quote.referenceRate {
                    LabeledContent(FinanceStrings.fxReferenceRate, value: "\(reference)")
                }
                if let margin = quote.marginPercent {
                    LabeledContent(FinanceStrings.fxMargin, value: "\(margin) %")
                }
                ForEach(quote.fees, id: \.labelKey) { fee in
                    LabeledContent(fee.labelKey, value: AmountEntry.format(fee.amount, fee.currency))
                }
                ForEach(quote.taxes, id: \.labelKey) { tax in
                    LabeledContent(tax.labelKey, value: AmountEntry.format(tax.amount, tax.currency))
                }
            }.padding(DesignTokens.spacingL).cardStyle()
            FinanceAmountSummary(title: FinanceStrings.total,
                                 value: AmountEntry.format(quote.totalDebit, quote.sourceCurrency))
            if !quote.executable {
                Label(FinanceStrings.fxIndicative, systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(AppColors.statusWarning)
            }
            Text(FinanceStrings.sendQuoteLimited).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
