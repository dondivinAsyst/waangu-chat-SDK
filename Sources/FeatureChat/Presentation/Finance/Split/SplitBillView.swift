//
//  SplitBillView.swift
//  FeatureChat
//
//  Partage d'addition — Bloc 6, chapitre 50.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Les partages d'addition de l'utilisateur.
struct SplitBillListView: View {

    let splits: any SplitBillManaging
    let sharing: any ShareSplitBillUseCaseProtocol
    let currentUserID: String
    let stepUp: any StepUpAuthenticating
    let conversationID: String?
    let deviceID: String
    /// Devise imposée par le serveur. `nil` tant que la session n'a pas répondu :
    /// on ne crée pas de partage dans une devise que l'app aurait choisie.
    let currency: String?
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var selected: SplitBill?
    @State private var isCreating = false

    private enum Phase {
        case loading
        case empty
        case loaded([SplitBill])
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
                case .loading: FinanceProgress(label: FinanceStrings.splitLoading)
                case .empty:   empty
                case .loaded(let list):
                    List(list) { split in
                        Button { selected = split } label: { row(split) }
                            .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                case .failed(let m): SplitFailure(text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.splitTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreating = true } label: {
                        Label(FinanceStrings.splitNew, systemImage: "plus")
                    }
                    .disabled(currency == nil)
                }
            }
            .financeDestination(item: $selected) { split in
                SplitBillDetailView(
                    splitID: split.id, splits: splits, currentUserID: currentUserID,
                    stepUp: stepUp, deviceID: deviceID,
                    onDismiss: { selected = nil; Task { await load() } }
                )
            }
            .financeDestination(isPresented: $isCreating) {
                SplitBillCreationView(
                    splits: splits, sharing: sharing, conversationID: conversationID, deviceID: deviceID,
                    currency: currency ?? "",
                    onCreated: { isCreating = false; Task { await load() } },
                    onDismiss: { isCreating = false }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        switch await splits.splits(cursor: nil) {
        case .success(let list):
            phase = list.isEmpty ? .empty : .loaded(list)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Rien à montrer — et l'écran dit **pourquoi**, sans parler à la place du
    /// serveur.
    ///
    /// « Aucun partage en cours » est une réponse du serveur. Tant qu'aucune
    /// route de liste n'existe, ce n'en est pas une : le client n'a rien
    /// demandé, et l'affirmer serait inventer une réponse. Créer reste possible
    /// dans les deux cas — `POST /split-bill` est bien servi.
    private var empty: some View {
        VStack(spacing: 16) {
            FinanceMessage(icon: "person.2",
                           text: splits.listsSplits ? FinanceStrings.splitEmpty
                                                    : FinanceStrings.splitListingUnavailable)
            Button(FinanceStrings.splitNew) { isCreating = true }
                .buttonStyle(.borderedProminent)
                .disabled(currency == nil)
        }
    }

    private func row(_ split: SplitBill) -> some View {
        let mine = split.participant(currentUserID)
        let isOrganizer = split.isOrganizer(currentUserID)

        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(split.labelKey).font(.subheadline.weight(.medium))
                SplitStateBadge(state: split.state)
                // L'avancement global n'est montré qu'à qui a le droit de le
                // voir : sinon participer à un dîner révèle qui traîne.
                if split.privacyScope.canSeeAggregate(isOrganizer: isOrganizer) {
                    Text(String(format: FinanceStrings.splitProgress,
                                money(split.collected), money(split.total)))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            if let mine {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(money(mine.share)).font(.subheadline).monospacedDigit()
                    SplitConsentBadge(consent: mine.consent)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func money(_ value: Money) -> String {
        AmountEntry.format(value.majorUnitsForDisplay, value.currency.code)
    }
}

/// Le détail d'un partage, et ce que l'utilisateur peut y faire.
///
/// L'échec, dit comme partout ailleurs dans la finance.
///
/// C'était un pictogramme système figé : la même panne montrait une animation
/// dans Payer une facture et un triangle immobile ici, alors que les deux
/// écrans disent la même chose.
private struct SplitFailure: View {
    let text: String

    var body: some View {
        VStack(spacing: 16) {
            FinanceWarningAnimation()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColors.subtitleGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// **Aucun débit sans consentement.** L'écran ne propose de payer qu'après
/// acceptation, et c'est le participant qui déclenche — jamais l'organisateur.
struct SplitBillDetailView: View {

    let splitID: String
    let splits: any SplitBillManaging
    let currentUserID: String
    let stepUp: any StepUpAuthenticating
    let deviceID: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading
    @State private var amountText = ""
    @State private var pendingContribution: Money?
    /// Les services de confirmation — ceux de Send Money, réutilisés.
    @Environment(\.financeFlowSurface) private var surface
    @Environment(\.financeObjectReader) private var objectReader

    private enum Phase {
        /// Issue inconnue après soumission — Bloc 10, §80. **Jamais un échec.**
        case uncertain(FinancialReference?)
        case loading
        case loaded(SplitBill)
        case reviewing(SplitBill, Money)
        /// Devis rendu par `/split-bill/pay` : frais, total, confirmation à
        /// accepter. Payer sa part suit exactement le chemin de Send Money.
        case confirmingQuote(SplitBill, Money, TransferQuote)
        case working
        case done(FinancialReference)
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .working: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .loaded, .reviewing: return !amountText.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        if case .reviewing(let split, _) = phase { return { phase = .loaded(split) } }
        return nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading: FinanceProgress(label: FinanceStrings.splitLoading)
                case .working: FinanceProgress(label: FinanceStrings.sendSubmitting)
                case .loaded(let split): detail(split)
                case .reviewing(let split, let amount): review(split, amount)
                case .confirmingQuote(let split, let amount, let quote):
                    quoteReview(split, amount, quote)
                case .done(let reference):
                    FinanceSubmissionView(reference: reference, onDismiss: onDismiss)
                case .uncertain(let reference):
                    FinanceUncertainOutcomeView(reference: reference,
                                                onCheckAgain: { Task { await load() } },
                                                onDismiss: onDismiss)
                case .failed(let m): SplitFailure(text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.splitTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .financeDestination(item: Binding(
                get: { pendingContribution.map(MoneyBox.init) },
                set: { if $0 == nil { pendingContribution = nil } }
            )) { box in
                StepUpGate(
                    authenticator: stepUp,
                    requiredLevel: .biometric,
                    reason: FinanceStrings.stepUpReasonSplit,
                    correlationID: CorrelationId(),
                    deviceID: deviceID,
                    onSatisfied: { attestation in
                        Task { await contribute(box.value, attestation: attestation) }
                    },
                    onCancel: { pendingContribution = nil }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    // MARK: - Actions

    private func load() async {
        phase = .loading
        switch await splits.split(id: splitID) {
        case .success(let split): phase = .loaded(split)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Accepter ou refuser. **Accepter n'est pas payer** : c'est reconnaître
    /// devoir sa part, et le paiement reste un geste séparé.
    private func respond(_ response: SplitParticipantResponse) async {
        phase = .working
        let submissionKey235 = await operationKeys.key(for: FinanceOperationKeys.scope("split.respond", splitID, String(describing: response)), deviceID: deviceID)
        let result = await splits.respond(
            splitID: splitID, response: response,
            idempotency: submissionKey235
        )
        switch result {
        case .success(let split): phase = .loaded(split)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Payer **sa** part : `POST /split-bill/pay`, qui rend un devis.
    ///
    /// Jamais un débit direct, et jamais le total : une part, un consentement
    /// (§4). Le devis se confirme ensuite comme celui d'un envoi.
    private func contribute(_ amount: Money, attestation: StepUpAttestation?) async {
        guard case .reviewing(let split, _) = phase, pendingContribution != nil else { return }
        pendingContribution = nil
        amountText = ""
        phase = .working
        let submissionKey250 = await operationKeys.key(for: FinanceOperationKeys.scope("split.pay", splitID, String(describing: amount)), deviceID: deviceID)
        switch await splits.payShare(splitID: splitID,
                                     conversationID: split.conversationID,
                                     amount: amount,
                                     idempotency: submissionKey250) {
        case .success(let quote):
            phase = .confirmingQuote(split, amount, quote)
        case .failure(let error) where FinancialOutcomeRoute.isFinalityUnknown(error):
            // L'objet porte la vérité : le relire dit si le paiement est passé.
            // Afficher un échec inviterait à payer une seconde fois.
            phase = .uncertain(nil)
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// La confirmation humaine, puis l'execute — la soumission partagée de
    /// Send Money : clé enregistrée, inscription avant l'envoi, relecture après.
    private func confirm(_ split: SplitBill, _ amount: Money, _ quote: TransferQuote) async {
        guard case .confirmingQuote = phase, let surface else { return }
        phase = .working
        let outcome = await TransferSubmission.confirm(
            quote,
            recipientID: split.organizerID,
            counterpartyName: nil,
            attestation: nil,
            sendMoney: surface.sendMoney,
            operationKeys: operationKeys,
            objects: objectReader,
            deviceID: deviceID
        )
        switch FinancialOutcomeRoute.route(outcome, submittedReference: quote.reference) {
        case .submitted(let reference):
            phase = .done(reference)
        case .needsNewAgreement:
            // Les conditions ont bougé : le nouveau devis, pas un nouveau départ.
            if case .needsNewAgreement(_, let fresh) = outcome {
                phase = .confirmingQuote(split, amount, fresh)
            }
        case .verifying(let reference):
            phase = .uncertain(reference)
        case .failed(.expired):
            // Devis expiré : on en redemande un, rien n'est parti.
            phase = .reviewing(split, amount)
            await contribute(amount, attestation: nil)
        case .failed(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Ce que le devis d'une part détaille : la part, les frais, le total.
    private static func quoteRows(_ quote: TransferQuote) -> [FinanceReviewSummary<Text>.Row] {
        var rows: [FinanceReviewSummary<Text>.Row] = [
            .init(FinanceStrings.splitMyShare, AmountEntry.format(quote.amount, quote.currency))
        ]
        if let fee = quote.feeAmount {
            rows.append(.init(FinanceStrings.fees,
                              AmountEntry.format(fee, quote.feeCurrency ?? quote.currency)))
        }
        if let total = quote.totalAmount {
            rows.append(.init(FinanceStrings.total,
                              AmountEntry.format(total, quote.totalCurrency ?? quote.currency),
                              isProminent: true))
        }
        return rows
    }

    /// Le devis d'une part, à accepter.
    private func quoteReview(_ split: SplitBill, _ amount: Money,
                             _ quote: TransferQuote) -> some View {
        QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
            VStack(spacing: 0) {
                QuoteValidityBanner(validity: validity) {
                    phase = .reviewing(split, amount)
                    Task { await contribute(amount, attestation: nil) }
                }
                FinanceReviewSummary(
                    title: FinanceStrings.flowReviewTitle,
                    amount: AmountEntry.format(quote.totalAmount ?? quote.amount,
                                               quote.totalCurrency ?? quote.currency),
                    amountCaption: split.labelKey,
                    rows: Self.quoteRows(quote)
                ) {
                    Text(FinanceStrings.sendQuoteLimited)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                }
                CustomButton(title: FinanceStrings.sendConfirm,
                             icon: "arrow.up.right", iconPosition: .trailing) {
                    Task { await confirm(split, amount, quote) }
                }
                .disabled(!validity.allowsConfirmation)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private func remind(_ participantID: String) async {
        phase = .working
        let submissionKey263 = await operationKeys.key(for: FinanceOperationKeys.scope("split.remind", splitID, participantID), deviceID: deviceID)
        let result = await splits.remind(
            splitID: splitID, participantID: participantID,
            idempotency: submissionKey263
        )
        switch result {
        case .success(let split): phase = .loaded(split)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    private func close() async {
        phase = .working
        let submissionKey274 = await operationKeys.key(for: FinanceOperationKeys.scope("split.close", splitID), deviceID: deviceID)
        switch await splits.close(splitID: splitID,
                                  idempotency: submissionKey274) {
        case .success(let split): phase = .loaded(split)
        case .failure(let error): phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func detail(_ split: SplitBill) -> some View {
        let isOrganizer = split.isOrganizer(currentUserID)
        let mine = split.participant(currentUserID)

        return Form {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(split.labelKey).font(.headline)
                    SplitStateBadge(state: split.state)
                }
            }

            if split.privacyScope.canSeeAggregate(isOrganizer: isOrganizer) {
                Section(FinanceStrings.detailSection) {
                    LabeledContent(FinanceStrings.total, value: money(split.total))
                    LabeledContent(FinanceStrings.splitCollected, value: money(split.collected))
                    if let remaining = split.remaining {
                        LabeledContent(FinanceStrings.splitRemaining, value: money(remaining))
                    }
                }
            }

            if let mine { mySection(split, mine) }

            participantsSection(split, isOrganizer: isOrganizer)

            if isOrganizer && !split.state.isTerminal {
                Section {
                    Button(FinanceStrings.splitClose, role: .destructive) {
                        Task { await close() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mySection(_ split: SplitBill, _ mine: SplitParticipant) -> some View {
        Section(FinanceStrings.splitMyShare) {
            LabeledContent(FinanceStrings.splitShare, value: money(mine.share))
            if mine.contributed.minorUnits > 0 {
                LabeledContent(FinanceStrings.splitContributed, value: money(mine.contributed))
            }
            SplitConsentBadge(consent: mine.consent)

            switch mine.consent {
            case .pending:
                // Le consentement d'abord. Rien ne peut être débité tant que
                // ce choix n'est pas fait.
                HStack {
                    Button(FinanceStrings.splitAccept) { Task { await respond(.accept) } }
                        .buttonStyle(.borderedProminent)
                    Button(FinanceStrings.splitDecline, role: .destructive) {
                        Task { await respond(.decline) }
                    }
                }

            case .accepted:
                if mine.hasOutstandingAmount, split.state.acceptsContributions {
                    HStack {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel(FinanceStrings.amount)
                        Text(mine.share.currency.code).foregroundStyle(.secondary)
                    }
                    Button(FinanceStrings.flowReview) {
                        if let amount = parsedAmount(currency: mine.share.currency) {
                            phase = .reviewing(split, amount)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedAmount(currency: mine.share.currency) == nil)

                    if let outstanding = mine.outstanding {
                        Button(String(format: FinanceStrings.splitPayFull, money(outstanding))) {
                            phase = .reviewing(split, outstanding)
                        }
                        .font(.caption)
                    }
                } else {
                    Text(FinanceStrings.splitSettled).font(.caption).foregroundStyle(.secondary)
                }

            case .declined:
                Text(FinanceStrings.splitDeclinedNote).font(.caption).foregroundStyle(.secondary)

            case .expired, .unknown:
                // Un consentement inconnu ou périmé n'autorise rien.
                Text(FinanceStrings.splitConsentUnavailable)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func review(_ split: SplitBill, _ amount: Money) -> some View {
        FinancePage {
            Text(FinanceStrings.splitMyShare).font(.title2.bold())
            LabeledContent(FinanceStrings.receiptReference, value: split.id)
            FinanceAmountSummary(title: FinanceStrings.amount, value: money(amount))
            Text(FinanceStrings.splitConsentNote).foregroundStyle(.secondary)
        } actions: {
            CustomButton(title: FinanceStrings.splitPayMyShare) { pendingContribution = amount }
        }
    }

    @ViewBuilder
    private func participantsSection(_ split: SplitBill, isOrganizer: Bool) -> some View {
        if split.privacyScope.canSeeOtherShares(isOrganizer: isOrganizer) {
            Section(FinanceStrings.splitParticipants) {
                ForEach(split.participants.filter { $0.userID != currentUserID }) { participant in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(participant.displayName).font(.subheadline)
                            SplitConsentBadge(consent: participant.consent)
                            if participant.isExcluded {
                                Text(FinanceStrings.splitExcluded)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(money(participant.share)).font(.caption).monospacedDigit()
                            // La relance est bornée : le §50 interdit les
                            // relances illimitées, qui font d'un partage un
                            // canal de harcèlement.
                            if isOrganizer,
                               split.reminderPolicy.allowsReminder(for: participant) {
                                Button(FinanceStrings.splitRemind) {
                                    Task { await remind(participant.userID) }
                                }
                                .font(.caption2)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            Section {
                Text(FinanceStrings.splitPrivateNote).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func parsedAmount(currency: CurrencyCode) -> Money? {
        guard let decimal = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              decimal > 0 else { return nil }
        return Money(minorUnits: NSDecimalNumber(decimal: decimal).int64Value, currency: currency)
    }

    private func money(_ value: Money) -> String {
        AmountEntry.format(value.majorUnitsForDisplay, value.currency.code)
    }
}

/// Crée un partage.
struct SplitBillCreationView: View {

    let splits: any SplitBillManaging
    /// Invitation des participants, et annonce du partage dans le fil de chacun.
    let sharing: any ShareSplitBillUseCaseProtocol
    let conversationID: String?
    let deviceID: String
    /// Devise du serveur, jamais choisie par l'app (`FinanceSessionStatus.currency`).
    let currency: String
    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onCreated: () -> Void
    let onDismiss: () -> Void

    @State private var label = ""
    @State private var totalText = ""
    /// Contacts choisis. Leur identifiant de compte devient `participantIDs`,
    /// leur numéro désigne le fil où chacun recevra le partage.
    @State private var participants: [UserContactProps] = []
    @State private var isChoosingParticipants = false
    /// Répartition choisie, et le montant ou le poids saisi pour chacun.
    @State private var strategy = SplitStrategyInput()
    @State private var privacyScope: SplitPrivacyScope = .ownShareOnly
    @State private var phase: Phase = .composing

    private enum Phase {
        case composing
        case reviewing
        case creating
        /// Créé au serveur ; annonce en cours dans le fil de chaque participant.
        case sharing
        /// Créé, mais pas annoncé à tous : ces noms ne l'ont pas reçu.
        case shareIncomplete([String])
        case failed(String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .creating, .sharing: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing, .reviewing: return !label.isEmpty || !totalText.isEmpty || !participants.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        if case .reviewing = phase { return { phase = .composing } }
        return nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .composing: form
                case .reviewing: review
                case .creating:  FinanceProgress(label: FinanceStrings.splitCreating)
                case .sharing:   FinanceProgress(label: FinanceStrings.splitSharing)
                case .shareIncomplete(let names): shareIncomplete(names)
                case .failed(let m): SplitFailure(text: m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.splitNew)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            // En feuille, comme le choix d'un bénéficiaire, et non poussé : poussé
            // depuis un écran lui-même poussé, il ne s'ouvrait pas.
            .chatAppearanceSheet(isPresented: $isChoosingParticipants) {
                FinanceNavigationScope {
                    FinanceParticipantsPicker(
                        sharing: sharing,
                        initialSelection: participants,
                        onDone: { chosen in
                            participants = chosen
                            isChoosingParticipants = false
                        },
                        onCancel: { isChoosingParticipants = false }
                    )
                }
                // L'environnement traverse la feuille : sans cela, la portée se
                // croirait déjà dans une pile et n'en créerait pas — ni titre,
                // ni recherche, ni boutons.
                .environment(\.financeHasNavigationStack, false)
            }
        }
    }

    private var participantIDs: [String] {
        participants.map(\.userId)
    }

    private var participantNames: String {
        participants.map(\.name).joined(separator: ", ")
    }

    private var draft: SplitBillDraft? {
        guard let decimal = Decimal(string: totalText.replacingOccurrences(of: ",", with: ".")),
              decimal > 0 else { return nil }

        guard let declared = strategy.strategy(for: participantIDs) else { return nil }

        // Exposant ISO 4217 de la devise du serveur : le montant saisi est en
        // unités majeures, le brouillon porte des unités mineures.
        let exponent = LiveInvoiceProvider.exponent(of: currency)
        let minor = decimal * pow(Decimal(10), exponent)

        return SplitBillDraft(
            labelKey: label.trimmingCharacters(in: .whitespacesAndNewlines),
            total: Money(minorUnits: NSDecimalNumber(decimal: minor).int64Value,
                         currency: CurrencyCode(code: currency, exponent: exponent)),
            participantIDs: participantIDs,
            strategy: declared,
            privacyScope: privacyScope,
            conversationID: conversationID
        )
    }

    private func create() async {
        guard case .reviewing = phase else { return }
        guard let draft, draft.isSubmittable else {
            phase = .failed(FinanceStrings.sendMissingAmount)
            return
        }
        phase = .creating
        // Une création relancée après erreur doit rendre le partage d'origine,
        // pas en créer un second : même brouillon, même clé.
        let idempotency = await operationKeys.key(
            for: FinanceOperationKeys.scope("split.create", String(describing: draft)),
            deviceID: deviceID
        )
        switch await splits.create(draft, idempotency: idempotency) {
        case .success(let split):
            // Le partage existe au serveur. Chacun le reçoit maintenant dans sa
            // conversation, où il verra qui a payé, refusé ou pas répondu.
            phase = .sharing
            let report = await sharing.share(
                split, correlationID: idempotency.correlationID, with: participants
            )
            if report.isComplete {
                onCreated()
            } else {
                let missed = participants
                    .filter { report.failed.contains($0.userId) }
                    .map(\.name)
                phase = .shareIncomplete(missed)
            }
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Le partage est créé — il n'est pas question de le recréer. On dit
    /// seulement qui ne l'a pas reçu dans sa conversation.
    private func shareIncomplete(_ names: [String]) -> some View {
        FinancePage {
            FinanceMessage(icon: "exclamationmark.bubble", text: FinanceStrings.splitShareIncomplete)
            Text(names.joined(separator: ", ")).font(.body.weight(.semibold))
        } actions: {
            CustomButton(title: FinanceStrings.splitParticipantsDone, action: onCreated)
        }
    }

    private var review: some View {
        FinancePage {
            Text(label).font(.title2.bold())
            if let draft {
                LabeledContent(FinanceStrings.total,
                               value: AmountEntry.format(draft.total.majorUnitsForDisplay, draft.total.currency.code))
                LabeledContent(FinanceStrings.splitStrategy, value: strategyTitle(strategy.kind))
                if strategy.kind == .equal {
                    LabeledContent(FinanceStrings.splitParticipants, value: participantNames)
                } else {
                    // Ce qui est déclaré pour chacun, tel que saisi : le backend
                    // en tire les parts, arrondis compris.
                    ForEach(participants, id: \.userId) { participant in
                        LabeledContent(participant.name, value: declaredValue(for: participant))
                    }
                }
                Text(FinanceStrings.splitRoundingNote).foregroundStyle(.secondary)
                Text(FinanceStrings.splitConsentNote).foregroundStyle(.secondary)
            }
        } actions: {
            CustomButton(title: FinanceStrings.splitCreate) { Task { await create() } }
        }
    }

    private func strategyTitle(_ kind: SplitStrategyInput.Kind) -> String {
        switch kind {
        case .equal:        return FinanceStrings.splitStrategyEqual
        case .custom:       return FinanceStrings.splitStrategyCustom
        case .proportional: return FinanceStrings.splitStrategyProportional
        }
    }

    private func declaredValue(for participant: UserContactProps) -> String {
        let text = strategy.values[participant.userId] ?? ""
        return strategy.kind == .custom ? "\(text) \(currency)" : text
    }

    /// Un champ par participant : le montant qu'il doit, ou son poids.
    @ViewBuilder
    private var perPersonSection: some View {
        let isCustom = strategy.kind == .custom
        Section {
            if participants.isEmpty {
                Text(FinanceStrings.splitParticipantsFirst)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.subtitleGray)
            } else {
                ForEach(participants, id: \.userId) { participant in
                    HStack(spacing: 12) {
                        Text(participant.name)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        TextField(isCustom ? "0" : "1", text: valueBinding(for: participant.userId))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .accessibilityLabel(participant.name)
                        if isCustom {
                            Text(currency).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text(isCustom ? FinanceStrings.splitCustomSection : FinanceStrings.splitWeightsSection)
        } footer: {
            perPersonFooter
        }
    }

    @ViewBuilder
    private var perPersonFooter: some View {
        if strategy.kind == .proportional {
            Text(FinanceStrings.splitWeightsHint)
        } else if let sum = strategy.customSum(for: participantIDs),
                  let total = SplitStrategyInput.decimal(totalText) {
            // Signalé, jamais bloqué : c'est le backend qui accepte ou refuse la
            // répartition, arrondis compris.
            VStack(alignment: .leading, spacing: 4) {
                Text(FinanceStrings.splitCustomSum(
                    AmountEntry.format(sum, currency), AmountEntry.format(total, currency)
                ))
                if sum != total {
                    Text(FinanceStrings.splitCustomMismatch).foregroundStyle(AppColors.primary)
                }
            }
        }
    }

    private func valueBinding(for userID: String) -> Binding<String> {
        Binding(
            get: { strategy.values[userID] ?? "" },
            set: { strategy.values[userID] = $0 }
        )
    }

    private var form: some View {
        Form {
            Section(FinanceStrings.splitLabel) {
                TextField(FinanceStrings.splitLabel, text: $label)
            }

            Section(FinanceStrings.amount) {
                HStack {
                    TextField("0", text: $totalText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(FinanceStrings.amount)
                    Text(currency).foregroundStyle(.secondary)
                }
            }

            Section(FinanceStrings.splitParticipants) {
                Button {
                    isChoosingParticipants = true
                } label: {
                    HStack {
                        Label(FinanceStrings.splitParticipantsChoose, systemImage: "person.2.badge.plus")
                            .foregroundStyle(AppColors.primary)
                        Spacer()
                        if !participants.isEmpty {
                            Text("\(participants.count)").foregroundStyle(.secondary)
                        }
                    }
                }
                if !participants.isEmpty {
                    Text(participantNames)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(FinanceStrings.splitStrategy) {
                Picker(FinanceStrings.splitStrategy, selection: $strategy.kind) {
                    ForEach(SplitStrategyInput.Kind.allCases) { kind in
                        Text(strategyTitle(kind)).tag(kind)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                // Les parts sont réparties par le serveur, arrondis compris :
                // un reste de division sur trois parts doit tomber quelque part,
                // et c'est une décision comptable.
                Text(FinanceStrings.splitRoundingNote).font(.caption).foregroundStyle(.secondary)
            }

            if strategy.kind != .equal {
                perPersonSection
            }

            Section(FinanceStrings.splitPrivacy) {
                Picker(FinanceStrings.splitPrivacy, selection: $privacyScope) {
                    Text(FinanceStrings.splitPrivacyOwn).tag(SplitPrivacyScope.ownShareOnly)
                    Text(FinanceStrings.splitPrivacyAggregate).tag(SplitPrivacyScope.aggregateOnly)
                    Text(FinanceStrings.splitPrivacyOpen).tag(SplitPrivacyScope.openToAll)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                CustomButton(title: FinanceStrings.flowReview) { phase = .reviewing }
                .disabled(draft?.isSubmittable != true)
                .financeActionRow()
            } footer: {
                Text(FinanceStrings.splitConsentNote).font(.caption)
            }
        }
    }
}

// MARK: - Badges

struct SplitConsentBadge: View {
    let consent: SplitParticipantConsent

    var body: some View {
        Label(label, systemImage: icon).font(.caption2).foregroundStyle(tint)
    }

    private var label: String {
        switch consent {
        case .pending:  return FinanceStrings.splitConsentPending
        case .accepted: return FinanceStrings.splitConsentAccepted
        case .declined: return FinanceStrings.splitConsentDeclined
        case .expired:  return FinanceStrings.splitConsentExpired
        case .unknown:  return FinanceStrings.splitConsentUnknown
        }
    }

    private var icon: String {
        switch consent {
        case .pending:  return "clock"
        case .accepted: return "checkmark.circle"
        case .declined: return "xmark.circle"
        case .expired:  return "clock.badge.xmark"
        case .unknown:  return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch consent {
        case .accepted: return .green
        case .pending:  return AppColors.primary
        default:        return .secondary
        }
    }
}

struct SplitStateBadge: View {
    let state: SplitSettlementState

    var body: some View {
        Text(label).font(.caption2).foregroundStyle(.secondary)
    }

    private var label: String {
        switch state {
        case .draft:            return FinanceStrings.splitStateDraft
        case .open:             return FinanceStrings.splitStateOpen
        case .partiallySettled: return FinanceStrings.splitStatePartial
        case .settled:          return FinanceStrings.splitStateSettled
        case .closed:           return FinanceStrings.splitStateClosed
        case .cancelled:        return FinanceStrings.splitStateCancelled
        case .expired:          return FinanceStrings.splitStateExpired
        case .unknown:          return FinanceStrings.splitStateUnknown
        }
    }
}

/// Enveloppe `Identifiable` pour présenter une feuille à partir d'un montant.
struct MoneyBox: Identifiable {
    let value: Money
    var id: String { "\(value.minorUnits)-\(value.currency.code)" }
    init(_ value: Money) { self.value = value }
}
