//
//  SendMoneyView.swift
//  FeatureChat
//
//  Parcours « envoyer de l'argent » — Bloc 3, chapitre 18.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Compose, fait chiffrer, puis exécute un envoi d'argent.
///
/// **Deux écrans en un, et la séparation compte.** La composition demande un
/// montant ; le récapitulatif montre ce que le backend facture réellement. Entre
/// les deux, aucun chiffre n'est calculé ici — frais, taxes, taux et total
/// viennent du devis. Un `amount * 0.02` écrit dans cette vue divergerait du
/// ledger au premier changement de barème.
struct SendMoneyView: View {

    let recipientResolver: any RecipientResolving

    /// Nom sous lequel l'émetteur connaît le bénéficiaire.
    ///
    /// Indication remise au résolveur, **jamais affichée telle quelle** : le
    /// nom montré reste celui du titulaire rendu par le backend.
    var recipientName: String?
    let quoting: any TransferQuoting
    let sendMoney: SendMoneyUseCase
    let recipientInput: RecipientInput
    let conversationID: String
    let currency: String
    let deviceID: String

    /// D'où part l'argent. `nil` ⇒ la ligne de source n'apparaît pas.
    ///
    /// Aucune garde n'en est tirée : c'est le backend qui refuse un envoi
    /// supérieur au disponible, et bloquer ici sur un solde peut-être périmé
    /// refuserait des envois légitimes.
    var fundingSources: (any FundingSourceProviding)?

    /// Montant proposé par le brouillon du Hub (§2.2). Pré-remplit le pavé
    /// s'il est vide ; l'utilisateur le corrige ou le garde, puis confirme.
    var initialAmount: Decimal? = nil

    let onDismiss: () -> Void

    @State private var nestedBusy = false
    @State private var phase: Phase = .resolving
    @State private var amountText: String = ""
    @State private var note: String = ""
    @State private var showsReview = false
    @State private var showsDiscard = false
    @State private var inputError: String?
    @State private var submittedReference: FinancialReference?
    /// Une seule reprise après déverrouillage — voir `FinanceConfirmRetry`.
    @State private var retriedAfterUnlock = false
    /// Le dernier échec vient d'une session verrouillée.
    @State private var failedLocked = false
    /// Le bénéficiaire du dernier envoi confirmé — ce que « Réessayer » redevise.
    @State private var lastRecipient: ResolvedRecipient?
    @Environment(\.financeFlowSurface) private var flowSurface

    /// Magasin des objets financiers — là où la réconciliation regarde.
    @Environment(\.financeObjectReader) private var objectReader
    @Environment(\.financeOperationKeys) private var operationKeys
    @State private var sources: [FundingSource] = []
    @State private var selectedSource: FundingSource?
    @FocusState private var noteFocused: Bool

    private enum Phase: Equatable {
        case resolving
        case unavailable(message: String)
        case composing(ResolvedRecipient)
        case quoting(ResolvedRecipient)
        case reviewing(ResolvedRecipient, TransferQuote)
        case submitting
        /// Les conditions ont bougé entre l'aperçu et la confirmation.
        case conditionsChanged(ResolvedRecipient, TransferQuote, [DecisionField])
        case done(FinancialReference)
        /// Issue inconnue après soumission — **jamais présentée comme un échec**.
        case verifying(FinancialReference)
        case failed(String)
    }

    /// L'écran affiché, pas la phase : c'est lui qui décide d'un glissement.
    ///
    /// Saisie, devis en cours, revue et conditions changées dessinent tous le
    /// compositeur à la racine — la revue est **poussée** par-dessus, elle ne le
    /// remplace pas. Animer sur la phase faisait glisser un compositeur
    /// identique au moment d'appuyer sur Envoyer, comme si l'on changeait de
    /// page pendant l'attente du devis, puis de nouveau au retour d'une erreur.
    private var screenStep: String {
        switch phase {
        case .composing, .quoting, .reviewing, .conditionsChanged: return "composer"
        default: return financeStepKey(phase)
        }
    }

    var body: some View {
        FinanceNavigationScope {
            rootContent
                .financePhase(screenStep)
                .navigationTitle(FinanceStrings.sendTitle)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showsReview) {
                    reviewContent
                        .navigationTitle(FinanceStrings.flowReview)
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationBarBackButtonHidden(phase == .submitting)
                        .toolbar { closeToolbar }
                }
                .toolbar { closeToolbar }
        }
        .onPreferenceChange(FinanceActivityBusyKey.self) { nestedBusy = $0 }
        .task(id: initialAmount) {
            if amountText.isEmpty, let initialAmount { amountText = "\(initialAmount)" }
        }
        .navigationBarBackButtonHidden(nestedBusy)
        .interactiveDismissDisabled(nestedBusy || phase == .submitting || !amountText.isEmpty || !note.isEmpty)
        // Le dialogue partagé des parcours, dans l'apparence de l'application —
        // voir `DialogConfiguration.financeDiscard`.
        .chatAppearanceDialog(
            isPresented: $showsDiscard,
            configuration: .financeDiscard(detail: .moneyEntry, onDiscard: onDismiss)
        )
        // Refus de devis, session à revalider, message du serveur : dans le
        // dialogue, pas sous le pavé numérique.
        .chatAppearanceDialog(
            isPresented: Binding(get: { inputError != nil },
                                 set: { if !$0 { inputError = nil } }),
            configuration: .financeError(message: inputError ?? "")
        )
        .onChange(of: showsReview) { _, visible in
            guard !visible else { return }
            switch phase {
            case .reviewing(let recipient, _), .conditionsChanged(let recipient, _, _):
                // Modifier un brouillon produit un nouveau devis, donc une
                // nouvelle clé : la clé est tirée de la référence du devis.
                phase = .composing(recipient)
            default: break
            }
        }
        .financeLoadOnce { if phase == .resolving { await resolve() } }
    }

    @ViewBuilder private var rootContent: some View {
        switch phase {
        case .resolving: FinanceProgress(label: FinanceStrings.checkingRecipient, animation: .searching)
        case .unavailable(let message): FinanceMessage(icon: "person.crop.circle.badge.questionmark", text: message)
        case .composing(let recipient), .quoting(let recipient),
             .reviewing(let recipient, _), .conditionsChanged(let recipient, _, _):
            composer(recipient)
        case .submitting: FinanceProgress(label: FinanceStrings.sendSubmitting)
        case .done(let reference): submitted(reference)
        case .verifying(let reference):
            FinanceSubmissionView(reference: reference,
                                  note: note,
                                  title: FinanceStrings.sendVerifyingTitle,
                                  detail: FinanceStrings.errorMessage(.timeoutUnknown),
                                  animation: .verifying,
                                  onDismiss: onDismiss)
        case .failed(let message):
            // Issue tranchée — l'incertain passe par `.verifying`. Réessayer
            // redemande un devis : nouveau prepare, nouvelle empreinte.
            FinanceFailureView(
                title: FinanceStrings.sendFailedTitle,
                message: message,
                reference: submittedReference?.id,
                locked: failedLocked,
                onRetry: lastRecipient.map { recipient in
                    {
                        retriedAfterUnlock = false
                        phase = .composing(recipient)
                        Task { await requestQuote(for: recipient) }
                    }
                },
                onDismiss: onDismiss
            )
        }
    }

    @ViewBuilder private var reviewContent: some View {
        switch phase {
        case .reviewing(let recipient, let quote): review(recipient, quote, changed: [])
        case .conditionsChanged(let recipient, let quote, let fields): review(recipient, quote, changed: fields)
        case .submitting: FinanceProgress(label: FinanceStrings.sendSubmitting)
        // Actualisation d'un devis expiré : l'écran de revue reste en place.
        case .quoting: FinanceProgress(label: FinanceStrings.sendQuoting)
        default: EmptyView()
        }
    }

    private func requestClose() {
        guard phase != .submitting, !nestedBusy else { return }
        switch phase {
        case .done, .verifying, .failed: onDismiss()
        default:
            if amountText.isEmpty && note.isEmpty { onDismiss() }
            else { showsDiscard = true }
        }
    }

    private var closeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(FinanceStrings.close) { requestClose() }
                .disabled(phase == .submitting || nestedBusy)
        }
    }

    // MARK: - Étapes

    private func resolve() async {
        phase = .resolving
        switch await recipientResolver.resolve(recipientInput, knownAs: recipientName) {
        case .success(let recipient):
            guard recipient.allowsPayment() else {
                phase = .unavailable(message: FinanceStrings.sendRecipientUnavailable)
                return
            }
            phase = .composing(recipient)
        case .failure(let error):
            phase = .unavailable(message: FinanceStrings.errorMessage(error))
        }
    }

    private func requestQuote(for recipient: ResolvedRecipient) async {
        guard case .composing = phase else { return }
        inputError = nil
        guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            inputError = FinanceStrings.sendMissingAmount
            return
        }

        phase = .quoting(recipient)

        let draft = TransferDraft(
            recipientID: recipient.recipientID,
            amount: amount,
            currency: currency,
            conversationID: conversationID,
            note: note.isEmpty ? nil : note,
            sourceID: selectedSource?.id
        )

        switch await quoting.quote(for: draft) {
        case .success(let quote):
            phase = .reviewing(recipient, quote)
            showsReview = true
        case .failure(let error):
            phase = .composing(recipient)
            inputError = FinanceStrings.errorMessage(error)
        }
    }

    private func confirm(_ recipient: ResolvedRecipient, _ quote: TransferQuote) async {
        switch phase {
        case .reviewing, .conditionsChanged: break
        default: return
        }
        phase = .submitting
        submittedReference = quote.reference
        lastRecipient = recipient

        // Clé enregistrée et inscription avant soumission : voir `TransferSubmission`.
        let outcome = await TransferSubmission.confirm(
            quote,
            recipientID: recipient.recipientID,
            counterpartyName: recipient.actor.displayName,
            attestation: nil,
            sendMoney: sendMoney,
            operationKeys: operationKeys,
            objects: objectReader,
            deviceID: deviceID
        )

        // Bloc 10, §80 — l'issue passe par une règle unique et testée.
        switch FinancialOutcomeRoute.route(outcome, submittedReference: quote.reference) {
        case .submitted(let reference):
            phase = .done(reference)
            showsReview = false

        case .needsNewAgreement:
            // Ne pas renvoyer l'utilisateur au début : lui montrer le nouveau
            // devis **et** ce qui a changé. Le renvoyer composer masquerait la
            // divergence, qui est précisément ce qu'il doit voir.
            if case .needsNewAgreement(let fields, let fresh) = outcome {
                phase = .conditionsChanged(recipient, fresh, fields)
            }

        case .verifying(let reference):
            // L'argent est peut-être parti. Afficher un échec inviterait à
            // repayer. L'opération est déjà dans le magasin — inscrite avant
            // soumission, puis relue — et la réconciliation la reprendra.
            phase = .verifying(reference)
            showsReview = false

        case .failed(.expired):
            // Expiré pendant la confirmation ou l'authentification : rien n'est
            // parti. Ce n'est pas un échec, c'est un devis à renouveler.
            await refreshQuote(recipient, expired: quote)

        case .failed(let error):
            if !retriedAfterUnlock,
               await FinanceConfirmRetry.sessionNowAllowsConfirm(after: error, session: flowSurface?.financeSession) {
                retriedAfterUnlock = true
                phase = .reviewing(recipient, quote)
                await confirm(recipient, quote)
                return
            }
            if case .capabilityUnavailable = error { failedLocked = true } else { failedLocked = false }
            phase = .failed(FinanceStrings.errorMessage(error))
            showsReview = false
        }
    }

    /// Demande un nouveau devis sans quitter la revue — Bloc 10, chapitre 80.
    ///
    /// D'abord le refresh du contrat (§3.2) : même opération, nouveau devis, à
    /// **reconfirmer** — la revue le montre à la place de l'ancien. S'il
    /// échoue, un nouveau prepare, comme avant.
    private func refreshQuote(_ recipient: ResolvedRecipient, expired: TransferQuote? = nil) async {
        if let expired, case .success(let fresh) = await quoting.refreshQuote(expired), !fresh.isExpired() {
            phase = .reviewing(recipient, fresh)
            return
        }
        phase = .composing(recipient)
        await requestQuote(for: recipient)
        // Le devis n'a pas pu être renouvelé : retour à la saisie, où l'erreur s'affiche.
        if case .composing = phase { showsReview = false }
    }

    // MARK: - Presentation

    /// Montant d'abord, pavé en bas, tout le reste visible entre les deux.
    ///
    /// L'ancienne version posait un `TextField` et laissait le clavier système
    /// remonter : il recouvrait le bénéficiaire et le bouton d'envoi, de sorte
    /// qu'on saisissait un montant sans plus voir à qui. Le pavé dessiné occupe
    /// une place fixe, et rien ne disparaît pendant la frappe.
    private func composer(_ recipient: ResolvedRecipient) -> some View {
        let isQuoting: Bool = { if case .quoting = phase { return true }; return false }()

        // Le clavier du motif recouvre le socle — bouton et pavé — sans le
        // retirer : voir `FinanceKeypadDock`.
        return FinanceKeypadDock {
            // `minHeight` calé sur la hauteur visible : sans lui, le `Spacer`
            // ci-dessous ne s'étire pas — une `ScrollView` propose une hauteur
            // infinie à son contenu, et un ressort y vaut zéro. C'est ce qui
            // laissait un vide fixe entre les cartes et le bouton pendant que
            // le montant restait tassé en haut.
            GeometryReader { viewport in
            ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 14) {
                    // Sans sélecteur de source, le montant se centre dans la
                    // hauteur libre : deux ressorts égaux, au-dessus et
                    // au-dessous. Posé en haut, il laissait un grand vide sans
                    // rien pour l'occuper. Avec le sélecteur, la colonne est
                    // assez chargée pour que le montant reste en tête.
                    if sources.isEmpty { Spacer(minLength: 12) }

                    AmountDisplay(digits: amountText,
                                  currencyCode: currency,
                                  fractionDigits: AmountEntry.fractionDigits(for: currency))
                        .padding(.top, sources.isEmpty ? 0 : 24)

                    // Le jeu disponible va au montant, pas au bas de l'écran.
                    Spacer(minLength: 12)

                    FinanceRecipientRow(recipient: recipient)
                        .padding(14)
                        .background(AppColors.cardBackground,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)

                    if !sources.isEmpty { sourceRow }

                    noteField
                        .id(Self.noteFieldID)
                        .financeScrollsIntoView(Self.noteFieldID, whileFocused: noteFocused, using: scroller)

                    Text(FinanceStrings.sendFeesLater)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 2)
                }
                .padding(.bottom, 12)
                .frame(minHeight: viewport.size.height, alignment: .top)
                // Toucher hors du champ ferme le clavier.
                .financeDismissesKeyboardOnBackgroundTap { noteFocused = false }
            }
            // La zone de saisie ne défile pas : le pavé et le bouton restent
            // sous le pouce quelle que soit la hauteur du contenu au-dessus.
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            }
            }
        } dock: {
            VStack(spacing: 12) {
                CustomButton(title: continueTitle,
                             isLoading: isQuoting,
                             isDisabled: amountText.isEmpty || AmountEntry.isBlank(amountText)) {
                    Task { await requestQuote(for: recipient) }
                }

                // Toujours présent : pendant la saisie du motif, le clavier le
                // recouvre. Le retirer faisait sauter l'écran à chaque focus.
                AmountKeypad(allowsDecimal: AmountEntry.fractionDigits(for: currency) > 0) { key in
                    AmountEntry.apply(key, to: &amountText,
                                      fractionDigits: AmountEntry.fractionDigits(for: currency))
                }
                .disabled(isQuoting)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(AppColors.walletCanvas)
        }
        .background(AppColors.walletCanvas)
        .task(id: currency) { await loadSources() }
    }

    /// D'où part l'argent, et de quoi en changer.
    private var sourceRow: some View {
        FundingSourcePicker(
            label: FinanceStrings.sendFrom,
            sources: sources,
            selection: $selectedSource
        ) { source in
            FundingSourcePicker.Descriptor(
                title: sourceTitle(source),
                subtitle: source.availableBalance.map { AmountEntry.format($0, source.currency) },
                symbol: Self.symbol(for: source.kind),
                isUsable: source.isUsable
            )
        }
        .padding(.horizontal, 16)
    }

    /// Nom, suivi de la fin d'identifiant quand il y en a une.
    private func sourceTitle(_ source: FundingSource) -> String {
        guard let masked = source.maskedIdentifier else { return source.name }
        return source.name + " •• " + masked
    }

    private static func symbol(for kind: FundingSource.Kind) -> String {
        switch kind {
        case .wallet:      return "wallet.bifold"
        case .card:        return "creditcard"
        case .bank:        return "building.columns"
        case .mobileMoney: return "iphone"
        }
    }


    private var continueTitle: String {
        guard !amountText.isEmpty, !AmountEntry.isBlank(amountText) else { return FinanceStrings.sendContinue }
        // Le bouton porte le montant : il est la dernière chose lue avant le
        // devis, et relire le chiffre là où l'on appuie évite l'envoi d'un
        // montant mal tapé.
        return FinanceStrings.sendAmountAction(AmountEntry.format(amountText, currency))
    }



    private static let noteFieldID = "send-money-note"

    private var noteField: some View {
        TextField(FinanceStrings.optional, text: $note, axis: .vertical)
            .lineLimit(1...3)
            .focused($noteFocused)
            .financeKeyboardDoneButton { noteFocused = false }
            .padding(14)
            .background(AppColors.cardBackground,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .accessibilityLabel(FinanceStrings.reason)
    }

    // MARK: - Saisie

    /// Applique une touche au montant.
    ///
    /// Trois règles, et chacune ferme une saisie que le backend refuserait :
    /// pas de second séparateur, pas plus de décimales que la devise n'en a,
    /// pas de zéro de tête.
    private func loadSources() async {
        guard let fundingSources, sources.isEmpty else { return }
        guard case .success(let resolved) = await fundingSources.sources(for: currency) else { return }
        await MainActor.run {
            sources = resolved
            // Présélection : celle que le backend désigne, sinon la première
            // utilisable. Jamais une source fermée — elle bloquerait l'envoi
            // sans que rien n'explique pourquoi.
            selectedSource = resolved.first { $0.isDefault && $0.isUsable }
                ?? resolved.first { $0.isUsable }
        }
    }

    /// Le récapitulatif de l'envoi.
    ///
    /// Le **total** est en tête, pas le montant saisi : c'est ce qui sera
    /// débité, frais compris, et c'est le seul chiffre que l'utilisateur doit
    /// retenir avant de confirmer. Le détail le décompose en dessous.
    ///
    /// L'avertissement de conditions modifiées reste **hors du défilement** :
    /// c'est la seule chose qui doit être lue avant le montant lui-même.
    private func review(_ recipient: ResolvedRecipient, _ quote: TransferQuote,
                        changed: [DecisionField]) -> some View {
        QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
        VStack(spacing: 0) {
            if !changed.isEmpty { changedTermsBanner(changed) }
            QuoteValidityBanner(validity: validity) { Task { await refreshQuote(recipient, expired: quote) } }

            FinanceReviewSummary(
                title: FinanceStrings.flowReviewTitle,
                amount: AmountEntry.format(quote.totalAmount ?? quote.amount,
                                           quote.totalCurrency ?? quote.currency),
                amountCaption: FinanceStrings.recipientTo + " " + recipient.actor.displayName,
                rows: reviewRows(quote)
            ) {
                Text(FinanceStrings.sendQuoteLimited)
                    .font(.footnote)
                    .foregroundStyle(AppColors.subtitleGray)
            }

            CustomButton(title: changed.isEmpty ? FinanceStrings.sendConfirm
                                                : FinanceStrings.sendAcceptNewTerms,
                         icon: "arrow.up.right", iconPosition: .trailing) {
                Task { await confirm(recipient, quote) }
            }
            .disabled(!validity.allowsConfirmation)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppColors.walletCanvas)
        }
    }

    private func reviewRows(_ quote: TransferQuote) -> [FinanceReviewSummary<Text>.Row] {
        var rows: [FinanceReviewSummary<Text>.Row] = [
            .init(FinanceStrings.amount, AmountEntry.format(quote.amount, quote.currency))
        ]
        if let fee = quote.feeAmount {
            rows.append(.init(FinanceStrings.fees,
                              AmountEntry.format(fee, quote.feeCurrency ?? quote.currency)))
        }
        if let tax = quote.taxAmount {
            rows.append(.init(FinanceStrings.taxes, AmountEntry.format(tax, quote.currency)))
        }
        if let rate = quote.exchangeRate {
            rows.append(.init(FinanceStrings.rate, "\(rate)"))
        }
        if let total = quote.totalAmount {
            rows.append(.init(FinanceStrings.total,
                              AmountEntry.format(total, quote.totalCurrency ?? quote.currency),
                              isProminent: true))
        }
        return rows
    }

    private func changedTermsBanner(_ changed: [DecisionField]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17))
                .foregroundStyle(AppColors.statusWarning)
            VStack(alignment: .leading, spacing: 3) {
                Text(FinanceStrings.termsChangedTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(FinanceStrings.termsChangedDetail(
                    changed.map { FinanceStrings.decisionFieldName($0.rawValue) }))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtitleGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.statusWarning.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    private func submitted(_ reference: FinancialReference) -> some View {
        // Le motif part avec la carte : c'est au destinataire qu'il s'adresse.
        FinanceSubmissionView(reference: reference, note: note, onDismiss: onDismiss)
    }

    private func amountRow(_ label: String, _ value: Decimal, _ code: String) -> some View {
        LabeledContent(label) { Text("\(value) \(code)").multilineTextAlignment(.trailing) }
            .accessibilityElement(children: .combine)
    }
}
