//
//  RequestMoneyView.swift
//  FeatureChat
//
//  Parcours « demander de l'argent » — Bloc 3, chapitre 17.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Compose une demande d'argent dans une conversation.
///
/// **Ordre imposé, et il n'est pas cosmétique.** La politique anti-abus est
/// consultée *avant* d'ouvrir le formulaire, jamais au moment d'envoyer :
/// laisser composer une demande pour la refuser ensuite est une friction
/// gratuite, et laisse croire que le refus est technique alors qu'il est
/// délibéré.
///
/// Le bénéficiaire est **résolu par le backend**, jamais déduit du fil. Le pair
/// d'une conversation n'est pas une identité financière : il peut avoir changé
/// de numéro, fermé son compte, ou ne jamais avoir eu de portefeuille.
struct RequestMoneyView: View {

    let recipientResolver: any RecipientResolving

    /// Nom sous lequel l'émetteur connaît le bénéficiaire.
    ///
    /// Indication remise au résolveur, **jamais affichée telle quelle** : le
    /// nom montré reste celui du titulaire rendu par le backend.
    var recipientName: String?
    /// Repli pour la partie de la demande — voir
    /// `MoneyRequestDraft.recipientChatUserID`. Ne dispense jamais de la
    /// résolution ci-dessous.
    var peerChatUserID: String? = nil
    let requests: any MoneyRequestCreating
    let recipientInput: RecipientInput
    let conversationID: String
    let currency: String
    /// Sans lui, deux appareils produiraient la même clé pour deux opérations
    /// distinctes — exactement ce que la clé d'idempotence doit empêcher.
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    /// Montant proposé par le brouillon du Hub (§2.2), pré-rempli s'il est vide.
    var initialAmount: Decimal? = nil
    let onDismiss: () -> Void

    @State private var phase: Phase = .resolving
    @State private var amountText: String = ""
    @State private var note: String = ""
    @State private var openAmount = false
    @State private var inputError: String?
    @FocusState private var noteFocused: Bool

    private enum Phase: Equatable {
        case resolving
        /// Le bénéficiaire n'a pas pu être établi.
        case unresolved(reasonKey: String)
        /// La politique refuse la demande avant même de composer.
        case refused(reasonKey: String)
        case composing(ResolvedRecipient)
        case reviewing(ResolvedRecipient)
        case submitting
        case submitted(FinancialReference)
        case failed(message: String)
    }

    private var flowIsBusy: Bool {
        switch phase {
        case .submitting: return true
        default: return false
        }
    }

    private var flowIsDirty: Bool {
        switch phase {
        case .composing, .reviewing: return openAmount || !amountText.isEmpty || !note.isEmpty
        default: return false
        }
    }

    private var flowBack: (() -> Void)? {
        switch phase {
        case .reviewing(let recipient): return { phase = .composing(recipient) }
        default: return nil
        }
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .resolving:      resolvingState
                case .unresolved(let key): messageState(icon: "person.crop.circle.badge.questionmark", key: key)
                case .refused(let key):    messageState(icon: "hand.raised", key: key)
                case .composing(let r):    composer(for: r)
                case .reviewing(let r): review(r)
                case .submitted(let reference):
                    // Le motif part aussi dans le fil : la demande dit au payeur
                    // à quoi sert l'argent, pas seulement combien.
                    FinanceSubmissionView(reference: reference, note: note.isEmpty ? nil : note,
                                          title: FinanceStrings.flowRequestSent,
                                          detail: FinanceStrings.requestNoDebitNotice, onDismiss: onDismiss)
                case .submitting:     submittingState
                case .failed(let m):  messageState(icon: "exclamationmark.triangle", literal: m)
                }
            }
            .financePhase(phase)
            .task(id: initialAmount) {
                if amountText.isEmpty, let initialAmount { amountText = "\(initialAmount)" }
            }
            .navigationTitle(FinanceStrings.requestTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, discardDetail: .moneyEntry, onClose: onDismiss)
        }
        .financeLoadOnce { await prepare() }
        // Même dialogue que Send Money : un refus s'acquitte, il ne se glisse
        // pas en rouge sous le pavé.
        .chatAppearanceDialog(
            isPresented: Binding(get: { inputError != nil },
                                 set: { if !$0 { inputError = nil } }),
            configuration: .financeError(message: inputError ?? "")
        )
    }

    // MARK: - Étapes

    /// Résolution puis politique — dans cet ordre, parce que la politique
    /// s'exprime *envers un bénéficiaire*, qui doit donc exister d'abord.
    private func prepare() async {
        phase = .resolving

        let resolution = await recipientResolver.resolve(recipientInput, knownAs: recipientName)
        guard case .success(let recipient) = resolution else {
            if case .failure(let error) = resolution,
               case .recipientUnresolved(let reason) = error {
                phase = .unresolved(reasonKey: reason.messageKey)
            } else {
                phase = .unresolved(reasonKey: "finance.recipient.unavailable")
            }
            return
        }

        // Un bénéficiaire bloqué, révoqué ou en délai de réflexion ne se
        // contourne pas en composant quand même.
        guard recipient.allowsPayment() else {
            phase = .refused(reasonKey: "finance.request.refused.recipient_not_eligible")
            return
        }

        let policyResult = await requests.policy(towards: recipient.recipientID)
        guard case .success(let policy) = policyResult else {
            phase = .refused(reasonKey: "finance.request.refused.policy_unavailable")
            return
        }

        // `openRequests` et `isContact` viendront du backend avec la politique.
        // Tant qu'ils manquent, on prend les valeurs les plus restrictives :
        // une demande jamais partie ne fait de mal à personne.
        let verdict = policy.verdictForNewRequest(openRequests: 0, isContact: true)
        switch verdict {
        case .allowed:
            phase = .composing(recipient)
        case .refused(let reasonKey):
            phase = .refused(reasonKey: reasonKey)
        }
    }

    private func submit(to recipient: ResolvedRecipient) async {
        guard case .reviewing = phase else { return }
        phase = .submitting

        let draft = MoneyRequestDraft(
            recipientID: recipient.recipientID,
            // Montant vide ⇒ montant libre, décidé par le payeur. Ce n'est pas
            // une erreur de saisie : c'est un cas d'usage du chapitre 17.
            amount: openAmount ? nil : Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")),
            currency: currency,
            conversationID: conversationID,
            note: note.isEmpty ? nil : note,
            recipientChatUserID: peerChatUserID
        )

        let submissionKey165 = await operationKeys.key(for: FinanceOperationKeys.scope("request.create", String(describing: draft)), deviceID: deviceID)
        let result = await requests.createRequest(
            draft,
            idempotency: submissionKey165
        )

        switch result {
        case .success(let reference):
            phase = .submitted(reference)
        case .failure(let error):
            phase = .failed(message: FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Presentation

    private var resolvingState: some View { FinanceProgress(label: FinanceStrings.checkingRecipient, animation: .searching) }
    private var submittingState: some View { FinanceProgress(label: FinanceStrings.requestSending) }
    private func messageState(icon: String, key: String? = nil, literal: String? = nil) -> some View {
        FinanceMessage(icon: icon, text: literal ?? localized(key ?? ""))
    }

    private func prepareReview(_ recipient: ResolvedRecipient) {
        inputError = nil
        if !openAmount {
            guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")), amount > 0 else {
                inputError = FinanceStrings.sendMissingAmount
                return
            }
        }
        phase = .reviewing(recipient)
    }

    /// Même composition que l'envoi : montant en tête, pavé en bas.
    ///
    /// Les deux écrans posent la même question — combien, et à qui — et les
    /// dessiner différemment obligeait à réapprendre l'un après l'autre. Seule
    /// la bascule de mode leur est propre.
    private func composer(for recipient: ResolvedRecipient) -> some View {
        // Le clavier du motif recouvre le socle — bouton et pavé — sans le
        // retirer : voir `FinanceKeypadDock`.
        FinanceKeypadDock {
            // `minHeight` calé sur la hauteur visible : sans lui le `Spacer`
            // ne s'étire pas — une `ScrollView` propose une hauteur infinie à
            // son contenu, et un ressort y vaut zéro.
            GeometryReader { viewport in
              ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 14) {
                        modePicker
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                        // Le montant cède la place à son explication.
                        //
                        // En montant libre il n'y a rien à saisir, et laisser
                        // le vide obligeait à deviner : « pas de montant » se
                        // lit aussi bien « montant zéro » que « le payeur
                        // décide ».
                        if openAmount {
                            FinanceInfoCard(
                                symbol: "hand.tap.fill",
                                title: FinanceStrings.requestOpenAmountTitle,
                                points: openAmountPoints(recipient)
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .trailing))
                            ))
                        } else {
                            // Une demande n'a pas de source à choisir : le
                            // montant se centre toujours dans la hauteur libre,
                            // entre ce ressort et celui sous le montant.
                            Spacer(minLength: 12)

                            AmountDisplay(digits: amountText,
                                          currencyCode: currency,
                                          fractionDigits: AmountEntry.fractionDigits(for: currency))
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .leading)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                ))
                        }

                        // Le jeu disponible va au montant, pas au bas de l'écran.
                        Spacer(minLength: 12)

                        FinanceRecipientRow(recipient: recipient)
                            .padding(14)
                            .background(AppColors.cardBackground,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 16)

                        noteField
                            .id(Self.noteFieldID)
                            .financeScrollsIntoView(Self.noteFieldID, whileFocused: noteFocused, using: scroller)

                        Text(FinanceStrings.requestNoDebitNotice)
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
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
              }
            }
        } dock: {
            VStack(spacing: 12) {
                CustomButton(title: FinanceStrings.flowReview,
                             isDisabled: !openAmount && AmountEntry.isBlank(amountText)) {
                    prepareReview(recipient)
                }

                // Pavé retiré en montant libre : il n'y a rien à saisir, et le
                // laisser inerte donnerait un écran qui ne répond pas.
                //
                // Pas pendant la saisie du motif : le clavier le recouvre
                // alors, et le retirer faisait sauter l'écran à chaque focus.
                if !openAmount {
                    AmountKeypad(
                        allowsDecimal: AmountEntry.fractionDigits(for: currency) > 0,
                        onKey: {
                            AmountEntry.apply($0, to: &amountText,
                                              fractionDigits: AmountEntry.fractionDigits(for: currency))
                        }
                    )
                    // Glisse depuis le bas : le pavé vient d'où il est, et
                    // surgir sur place le faisait paraître déjà présent.
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(AppColors.walletCanvas)
        }
        .background(AppColors.walletCanvas)
    }

    /// La bascule, **animée**.
    ///
    /// L'animation est portée par la liaison et non par un `onChange` : le
    /// changement d'état et les transitions doivent appartenir à la même
    /// transaction, sinon le contenu commute sèchement pendant que le segment,
    /// lui, glisse — c'est ce qui se passait.
    private var modePicker: some View {
        Picker(FinanceStrings.amount, selection: animatedMode) {
            Text(FinanceStrings.flowSetAmount).tag(false)
            Text(FinanceStrings.flowPayerChooses).tag(true)
        }
        .pickerStyle(.segmented)
    }

    private var animatedMode: Binding<Bool> {
        Binding(
            get: { openAmount },
            set: { isOpen in
                withAnimation(.snappy(duration: 0.28)) {
                    openAmount = isOpen
                    // Passer en montant libre efface la saisie : conserver un
                    // montant invisible le ferait réapparaître au retour, sans
                    // que rien ne l'ait annoncé.
                    if isOpen { amountText = "" }
                    inputError = nil
                }
            }
        )
    }

    /// Ce que le mode « le payeur choisit » implique, dit au futur.
    private func openAmountPoints(_ recipient: ResolvedRecipient) -> [String] {
        [
            FinanceStrings.requestOpenAmountReceives(recipient.actor.displayName),
            FinanceStrings.requestOpenAmountChooses,
            FinanceStrings.requestOpenAmountNoDebit
        ]
    }

    private static let noteFieldID = "request-money-note"

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


    /// Applique une touche au montant. Mêmes règles que l'envoi : pas de second
    /// séparateur, pas plus de décimales que la devise n'en a, pas de zéro de
    /// tête.
    private func review(_ recipient: ResolvedRecipient) -> some View {
        VStack(spacing: 0) {
            FinanceReviewSummary(
                title: FinanceStrings.flowReview,
                // En montant libre, la tête porte la **phrase** et non un
                // chiffre : il n'y en a pas, et « 0 » se lirait comme une
                // demande de zéro.
                amount: openAmount ? nil : AmountEntry.format(amountText, currency),
                amountCaption: FinanceStrings.recipientTo + " " + recipient.actor.displayName,
                rows: reviewRows
            ) {
                Text(FinanceStrings.requestNoDebitNotice)
                    .font(.footnote)
                    .foregroundStyle(AppColors.subtitleGray)
            }

            CustomButton(title: FinanceStrings.requestSubmit) {
                Task { await submit(to: recipient) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppColors.walletCanvas)
    }

    private var reviewRows: [FinanceReviewSummary<Text>.Row] {
        var rows: [FinanceReviewSummary<Text>.Row] = [
            .init(FinanceStrings.amount,
                  openAmount ? FinanceStrings.flowPayerChooses
                             : AmountEntry.format(amountText, currency),
                  isProminent: !openAmount)
        ]
        if !note.isEmpty { rows.append(.init(FinanceStrings.reason, note)) }
        return rows
    }

    private func localized(_ key: String) -> String {
        // Repli capitalisé conservé en dernier recours, mais la résolution
        // passe d'abord par TranslationKit : sans cela une clé de protocole
        // comme « UNDETERMINED » s'affichait telle quelle.
        FinanceLocalization.string(
            key,
            fallback: key.replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: ".", with: " ").capitalized
        )
    }
}

