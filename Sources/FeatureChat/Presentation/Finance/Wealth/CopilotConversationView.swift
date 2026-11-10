//
//  CopilotConversationView.swift
//  FeatureChat
//
//  Waangu Copilot (§8) — la conversation, où l'opération se mène jusqu'au bout.
//

import SwiftUI
import AVFoundation
import WaanguSharedUI
import WaanguCoreKit

/// Waangu Copilot : on lui écrit, ou on touche une action ; il pose les
/// questions, montre le devis du serveur, et l'on confirme **dans le fil**.
///
/// La confirmation reste un geste de l'utilisateur, suivi de Face ID ou du code.
/// Le fil disparaît à la fermeture : rien n'est gardé sur l'appareil.
struct CopilotConversationView: View {

    @StateObject private var model: CopilotConversationViewModel
    @State private var input = ""
    /// Les chiffres tapés dans la feuille de PIN — jamais conservés au-delà.
    @State private var pin = ""
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    /// Le menu des commandes, ouvert par le bouton de la barre de saisie.
    @State private var commandsOpen = false

    // Le fil se dévoile message par message : une bulle s'écrit lettre à lettre,
    // la suite attend qu'elle ait fini — comme le font les assistants.
    /// Messages montrés, dans l'ordre du modèle.
    @State private var revealed = 0
    /// La bulle qui s'écrit, s'il y en a une.
    @State private var typing: UUID?
    /// Avance à chaque groupe de lettres : la bulle grandit, le fil la suit.
    @State private var typingProgress = 0

    private let objectReader: (any FinancialObjectUseCasesProtocol)?
    private let disputes: any DisputeFiling
    /// Une opération que le fil ne mène pas encore : son écran, avec ce que
    /// Copilot a compris.
    let onOpen: (FinanceTextDraft) -> Void
    let onDismiss: () -> Void
    /// Poussée dans la pile des discussions, comme une conversation : le bouton
    /// retour du système, pas « Fermer ».
    let isPushed: Bool

    init(surface: ChatFinanceSurface,
         host: CopilotConversationHost?,
         hubKinds: [FinanceEntryKind] = [],
         closedHubActions: [FinanceEntryKind: String] = [:],
         directMessaging: WalletPaymentFlowViewModel? = nil,
         conversationStore: (any CopilotConversationStoring)? = nil,
         isPushed: Bool = false,
         onOpen: @escaping (FinanceTextDraft) -> Void,
         onDismiss: @escaping () -> Void) {
        _model = StateObject(wrappedValue: CopilotConversationViewModel(surface: surface, host: host,
                                                                                hubKinds: hubKinds,
                                                                                directMessaging: directMessaging,
                                                                                conversationStore: conversationStore,
                                                                                closedHubActions: closedHubActions))
        self.objectReader = surface.objectReader
        self.disputes = surface.disputes
        self.isPushed = isPushed
        self.onOpen = onOpen
        self.onDismiss = onDismiss
    }

    var body: some View {
        FinanceNavigationScope {
            VStack(spacing: 0) {
                if isPushed { chatHeader }
                thread
                if commandsOpen || slashQuery != nil {
                    // Le bouton, ou « / » : les commandes, à la place des réponses proposées.
                    slashMenu(slashQuery ?? "")
                } else {
                    // Les réponses proposées suivent la question : elles attendent qu'elle soit écrite.
                    if caughtUp && model.step == .recipient { recipientChoices }
                    if caughtUp && (model.step == .choice || model.step == .text) && !model.options.isEmpty { optionChips }
                }
                inputBar
            }
            .background { roomBackground }
            .navigationTitle(FinanceStrings.copilotName)
            .navigationBarTitleDisplayMode(.inline)
            // Poussée depuis la liste : l'en-tête est celui d'une conversation.
            .toolbar(isPushed ? .hidden : .automatic, for: .navigationBar)
            .modifier(CopilotTaskControls(isPushed: isPushed, isBusy: model.isWorking, onClose: onDismiss))
            // Repli de Face ID : la feuille de PIN du portefeuille, comme hors du chat.
            .pinEntryOverlay(
                show: Binding(get: { model.pinRequest != nil }, set: { _ in }),
                pin: $pin,
                title: FinanceStrings.copilotPINTitle,
                digitCount: 6,
                clearPinOnDismiss: true,
                onComplete: { entered in
                    pin = ""
                    Task { await model.submitPIN(entered) }
                },
                onDismiss: { model.cancelPIN() })
        }
        .task { await model.load() }
        .onChange(of: model.step) { step in
            commandsOpen = false
            input = ""
            inputFocused = step == .amount || step == .text
        }
    }

    // MARK: - Fil

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    intro
                    if !model.suggestions.isEmpty { chips }
                    ForEach(Array(model.messages.prefix(revealed))) { message in
                        row(message)
                            .id(message.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    // En attendant le serveur : les trois points du « en train d'écrire ».
                    if model.isWorking && caughtUp {
                        TypingDots()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityElement()
                            .accessibilityLabel(FinanceStrings.copilotWorking)
                            .id("working")
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _ in advance() }
            .onChange(of: revealed) { _ in
                guard revealed > 0 else { return }
                let last = model.messages[revealed - 1].id
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onChange(of: typingProgress) { _ in
                // Sans animation : à chaque lettre, une animation ferait trembler le fil.
                guard let typing else { return }
                proxy.scrollTo(typing, anchor: .bottom)
            }
            .onChange(of: model.isWorking) { working in
                guard working, caughtUp else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("working", anchor: .bottom) }
            }
        }
    }

    /// Tout est montré, et plus rien ne s'écrit.
    private var caughtUp: Bool { typing == nil && revealed == model.messages.count }

    /// Montre les messages suivants. Une bulle de Copilot ou de l'app s'écrit,
    /// et la suite attend ; le reste (cartes, avis, vos messages) paraît aussitôt.
    private func advance() {
        guard typing == nil else { return }
        // Relus de l'appareil : déjà lus, montrés entiers, sans s'écrire à nouveau.
        if revealed < model.restoredCount { revealed = model.restoredCount }
        while revealed < model.messages.count {
            let next = model.messages[revealed]
            withAnimation(.easeOut(duration: 0.2)) { revealed += 1 }
            if Self.isTyped(next) && !reduceMotion {
                typing = next.id
                return
            }
        }
    }

    private func finishedTyping(_ id: UUID) {
        guard typing == id else { return }
        typing = nil
        advance()
    }

    private static func isTyped(_ message: CopilotConversationViewModel.Message) -> Bool {
        switch message {
        case .copilot, .question: return true
        default:                  return false
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundStyle(AppColors.primary)
                .accessibilityHidden(true)
            Text(FinanceStrings.copilotIntroPrepare)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.subtitleGray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.suggestions) { suggestion in
                    chip(CopilotConversationViewModel.title(of: suggestion)) {
                        Task { await model.choose(suggestion) }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppColors.primary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isWorking)
    }

    @ViewBuilder
    private func row(_ message: CopilotConversationViewModel.Message) -> some View {
        switch message {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .font(bubbleFont)
                    // Blanc fixe sur la couleur primaire : `AppColors.white` vire
                    // au quasi-noir en mode sombre.
                    .foregroundStyle(isPushed ? ChatBubbleStyle.foreground(for: colorScheme) : Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .modifier(CopilotBubble(direction: .sent, chatRoom: isPushed))
            }
        case .copilot(let id, let text, let authoritative):
            // Les mots de Copilot, légendés : rien ne doit les lire comme un fait.
            VStack(alignment: .leading, spacing: 4) {
                if !authoritative {
                    Text(FinanceStrings.copilotName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                        .padding(.leading, 6)
                }
                assistantBubble(text, id: id)
            }
        case .question(let id, let text):
            assistantBubble(text, id: id)
        case .proposal(_, let proposal):
            proposalCard(proposal)
        case .recipient(_, let card):
            recipientCard(card)
        case .quote(let id, let card):
            quoteCard(id, card)
        case .requestReview(let id, let card):
            requestCard(id, card)
        case .bill(_, let card):
            billCard(card)
        case .scanner(let id, let state):
            switch state {
            case .active:
                CopilotQRScanCard { payload in Task { await model.scanned(id, payload: payload) } }
            case .scanned, .closed:
                Label(state == .scanned ? FinanceStrings.copilotScanned : FinanceStrings.copilotScannerClosed,
                      systemImage: "qrcode.viewfinder")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtitleGray)
                    .frame(maxWidth: .infinity)
            }
        case .outcome(_, let reference):
            if reference.type == .dispute {
                // Un litige se suit par ses propres routes : `/objects/` ne le connaît pas.
                CopilotDisputeCard(reference: reference, disputes: disputes)
            } else {
            CopilotOutcomeCard(
                reference: reference, reader: objectReader,
                // Signaler un problème sur cette opération — pas sur un litige déjà ouvert.
                onReport: reference.type == .dispute ? nil
                    : { Task { await model.reportProblem(on: reference) } },
                onRefund: { Task { await model.requestRefund(on: reference) } },
                onReverse: { Task { await model.requestReversal(on: reference) } },
                onShareReceipt: model.canShareReceipts
                    ? { Task { await model.shareReceipt(of: reference) } } : nil,
                onCancel: { Task { await model.requestCancel(on: reference) } },
                onIssueLink: reference.type == .moneyRequest && model.canIssuePaymentLinks
                    ? { Task { await model.issuePaymentLink(for: reference) } } : nil)
            }
        case .cashOutCode(_, let token):
            CashOutCodeCard(token: token)
        case .paymentLink(_, let url, let expiresAt):
            paymentLinkCard(url, expiresAt)
        case .announceFailed(let id, let resolved):
            // Comme le reçu de l'écran d'envoi : le message manque, l'opération est faite.
            if !resolved {
                VStack(spacing: 6) {
                    Text(FinanceStrings.flowBubbleFailed)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.subtitleGray)
                        .multilineTextAlignment(.center)
                    Button(FinanceStrings.flowShareInChat) { Task { await model.retryAnnouncement(id) } }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                        .disabled(model.isWorking)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        case .notice(_, let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.subtitleGray)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 4)
        }
    }

    /// Une bulle à gauche : Copilot ou l'app. La dernière arrivée s'écrit lettre à lettre.
    private func assistantBubble(_ text: String, id: UUID) -> some View {
        HStack {
            CopilotTypingText(text: text, animate: typing == id,
                              onProgress: { typingProgress += 1 },
                              onFinished: { finishedTyping(id) })
                .font(bubbleFont)
                .foregroundStyle(isPushed ? ChatBubbleStyle.foreground(for: colorScheme) : AppColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .modifier(CopilotBubble(direction: .received, chatRoom: isPushed))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 48)
        }
    }

    /// Le lien de paiement, à partager. Contexte seulement : payer demande le consentement du payeur.
    private func paymentLinkCard(_ url: String, _ expiresAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FinanceStrings.copilotPaymentLinkTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Text(url)
                .font(.system(size: 12).monospaced())
                .foregroundStyle(AppColors.subtitleGray)
                .lineLimit(2)
                .textSelection(.enabled)
            if let expiresAt {
                Text(FinanceStrings.cashOutCodeExpires(expiresAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.subtitleGray)
            }
            Text(FinanceStrings.copilotPaymentLinkNote)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.subtitleGray)
            if let shared = URL(string: url) {
                ShareLink(item: shared) {
                    Label(FinanceStrings.copilotShareLink, systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recipientCard(_ card: CopilotConversationViewModel.RecipientCard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(AppColors.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                if card.verified {
                    Label(FinanceStrings.copilotRecipientVerified, systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.primary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Le devis du serveur. Confirmable tant qu'il vaut ; expiré, il s'actualise.
    private func quoteCard(_ id: UUID, _ card: CopilotConversationViewModel.QuoteCard) -> some View {
        let quote = card.quote
        return QuoteValidityReader(expiresAt: quote.expiresAt) { validity in
            VStack(alignment: .leading, spacing: 10) {
                Text(card.titleOverride ?? CopilotConversationViewModel.title(of: card.kind))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                VStack(spacing: 6) {
                    if !card.recipientName.isEmpty {
                        quoteRow(card.recipientLabel, card.recipientName)
                    }
                    quoteRow(FinanceStrings.amount, AmountEntry.format(quote.amount, quote.currency))
                    if let fee = quote.feeAmount {
                        quoteRow(FinanceStrings.fees, AmountEntry.format(fee, quote.feeCurrency ?? quote.currency))
                    }
                    if let total = quote.totalAmount {
                        quoteRow(FinanceStrings.total, AmountEntry.format(total, quote.totalCurrency ?? quote.currency),
                                 prominent: true)
                    }
                }
                switch card.state {
                case .open:
                    if validity.allowsConfirmation {
                        CustomButton(title: FinanceStrings.sendConfirm, icon: "faceid") {
                            inputFocused = false
                            Task { await model.confirm(id) }
                        }
                        .disabled(model.isWorking)
                        // Toujours offert, même si `nextSafeActions` ne contient pas
                        // `CANCEL` : annuler ici n'envoie rien au serveur, et
                        // l'utilisateur doit toujours pouvoir renoncer avant de payer.
                        Button(FinanceStrings.cancel) { model.cancel(id) }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.primary)
                            .frame(maxWidth: .infinity)
                            .disabled(model.isWorking)
                    } else {
                        QuoteValidityBanner(validity: validity) { Task { await model.refreshQuote(id) } }
                    }
                case .confirming:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(FinanceStrings.sendSubmitting)
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.subtitleGray)
                    }
                case .closed:
                    EmptyView()
                }
            }
            .padding(14)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(card.state == .closed ? 0.55 : 1)
        }
    }

    /// La facture telle que le Biller Hub l'a lue — le dû, avant tout devis.
    private func billCard(_ card: CopilotConversationViewModel.BillCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.billerName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            VStack(spacing: 6) {
                if !card.customer.isEmpty { quoteRow(card.customerLabel, card.customer) }
                quoteRow(FinanceStrings.billAmountDue, AmountEntry.format(card.amountDue, card.currency),
                         prominent: true)
                if let due = card.dueDate {
                    quoteRow(FinanceStrings.billDueDate, due.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Une demande à envoyer : aucun débit, donc pas de Face ID.
    private func requestCard(_ id: UUID, _ card: CopilotConversationViewModel.RequestCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CopilotConversationViewModel.title(of: .requestMoney))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            VStack(spacing: 6) {
                if !card.recipientName.isEmpty { quoteRow(FinanceStrings.copilotRequestFrom, card.recipientName) }
                quoteRow(FinanceStrings.amount, AmountEntry.format(card.amount, card.currency), prominent: true)
            }
            Text(FinanceStrings.requestNoDebitNotice)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.subtitleGray)
                .fixedSize(horizontal: false, vertical: true)
            switch card.state {
            case .open:
                CustomButton(title: FinanceStrings.copilotRequestSend, icon: "paperplane") {
                    inputFocused = false
                    Task { await model.sendRequest(id) }
                }
                .disabled(model.isWorking)
                Button(FinanceStrings.cancel) { model.cancel(id) }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .disabled(model.isWorking)
            case .confirming:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(FinanceStrings.requestSending)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.subtitleGray)
                }
            case .closed:
                EmptyView()
            }
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(card.state == .closed ? 0.55 : 1)
    }

    private func quoteRow(_ label: String, _ value: String, prominent: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.subtitleGray)
            Spacer()
            Text(value)
                .font(.system(size: prominent ? 17 : 15, weight: prominent ? .bold : .regular))
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// Un parcours que le fil ne mène pas encore. Le montant est **candidat**.
    private func proposalCard(_ proposal: CopilotConversationViewModel.Proposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(CopilotConversationViewModel.title(of: proposal.kind))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                if let amount = proposal.amount, let currency = proposal.currency {
                    Text("· " + AmountEntry.format(amount, currency))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .monospacedDigit()
                }
            }
            Text(FinanceStrings.copilotProposalDetail)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.subtitleGray)
                .fixedSize(horizontal: false, vertical: true)
            CustomButton(title: FinanceStrings.copilotOpenReview) {
                onOpen(FinanceTextDraft(kind: proposal.kind, amount: proposal.amount, currency: proposal.currency))
            }
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Saisie

    /// Bénéficiaires proposés, filtrés par ce qui est tapé (ou par l'indice lu
    /// dans la demande).
    private var recipientChoices: some View {
        let query = input.isEmpty ? (model.recipientHint ?? "") : input
        var shown = CopilotConversationViewModel.matches(model.recipientChoices, query: query)
        if shown.isEmpty { shown = model.recipientChoices }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shown.prefix(12)) { choice in
                    Button {
                        Task { await model.pick(choice) }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(choice.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.primary)
                            if let detail = choice.detail {
                                Text(detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.subtitleGray)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.primary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isWorking)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 6)
    }

    /// Réponses proposées : catégorie, facturier, valeur admise, « Passer ».
    private var optionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.options) { option in
                    chip(option.title) { Task { await model.choose(option) } }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 6)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                // Les commandes sans taper « / » — comme Slack ou Telegram.
                Button {
                    inputFocused = false
                    withAnimation(.easeOut(duration: 0.2)) { commandsOpen.toggle() }
                } label: {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.primary)
                }
                .accessibilityLabel(FinanceStrings.copilotSlashTitle)
                TextField(placeholder, text: $input, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .keyboardType(model.step == .amount ? .decimalPad
                                  : (model.step == .text && model.textIsNumeric ? .numberPad : .default))
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(submit)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            // Une demande tapée, pas une commande : le menu se referme.
            .onChange(of: input) { text in
                if commandsOpen && !text.isEmpty && !text.hasPrefix("/") { commandsOpen = false }
            }
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? AppColors.primary : AppColors.subtitleGray.opacity(0.5))
            }
            .disabled(!canSend)
            .accessibilityLabel(FinanceStrings.copilotSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background { inputBarBackground }
    }

    @ViewBuilder
    private var inputBarBackground: some View {
        if isPushed {
            // Le matériau de la barre de saisie d'une conversation.
            Rectangle().fill(Material.regular).ignoresSafeArea(edges: .bottom)
        } else {
            AppColors.walletCanvas
        }
    }

    // MARK: - Allure d'une conversation (poussée depuis la liste)

    /// Le corps de texte d'une conversation ; celui de la feuille, sinon.
    private var bubbleFont: Font { isPushed ? .body : .system(size: 15) }

    /// Le fond d'une conversation — l'image du chat —, ou celui des paiements.
    @ViewBuilder
    private var roomBackground: some View {
        if isPushed {
            Image("chatBackground", bundle: .module)
                .resizable()
                .ignoresSafeArea()
        } else {
            AppColors.walletCanvas
        }
    }

    /// L'en-tête d'une conversation : retour, avatar, nom — sans appel ni présence.
    private var chatHeader: some View {
        HStack(spacing: 8) {
            Button {
                inputFocused = false
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .foregroundStyle(.primary)
            }
            // Une opération en cours ne s'abandonne pas d'un geste.
            .disabled(model.isWorking)
            .accessibilityLabel(FinanceStrings.close)

            HStack(alignment: .center, spacing: 8) {
                CopilotAvatar(size: 40)
                Text(FinanceStrings.copilotName)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Commandes « / »

    /// Ce qui suit « / », tant que la commande s'écrit — un espace la referme.
    private var slashQuery: String? {
        guard input.hasPrefix("/"), !input.contains(where: { $0.isWhitespace }) else { return nil }
        return String(input.dropFirst())
    }

    private func slashMenu(_ query: String) -> some View {
        let matches = CopilotConversationViewModel.slashMatches(model.slashCommands, query: query)
        return VStack(alignment: .leading, spacing: 0) {
            Text(FinanceStrings.copilotSlashTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.subtitleGray)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
            if matches.isEmpty {
                Text(FinanceStrings.copilotSlashNoMatch)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.subtitleGray)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, command in
                            Button { run(command) } label: { slashRow(command) }
                                .buttonStyle(.plain)
                                .disabled(model.isWorking)
                            if index < matches.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
                // Cinq lignes au plus ; au-delà, la liste défile.
                .frame(height: min(CGFloat(matches.count), 5) * Self.slashRowHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private static let slashRowHeight: CGFloat = 44

    /// Une icône et un titre traduit — ce qu'un utilisateur a besoin de lire.
    private func slashRow(_ command: CopilotConversationViewModel.SlashCommand) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 30, height: 30)
                .background(AppColors.primary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(command.unavailableReason == nil ? AppColors.textPrimary : AppColors.subtitleGray)
                    .lineLimit(1)
                // Fermée par le Hub : son motif, tel que le serveur l'a rédigé.
                if let reason = command.unavailableReason {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.subtitleGray)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.slashRowHeight)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }

    /// Comme la puce : l'opération en cours s'abandonne, la commande commence.
    private func run(_ command: CopilotConversationViewModel.SlashCommand) {
        commandsOpen = false
        input = ""
        Task { await model.choose(command.suggestion) }
    }

    private var placeholder: String {
        switch model.step {
        case .recipient: return FinanceStrings.copilotRecipientPlaceholder
        case .amount:    return FinanceStrings.copilotAmountPlaceholder(model.currency)
        case .text:      return model.textPrompt
        case .free, .choice: return FinanceStrings.copilotPlaceholder
        }
    }

    private var canSend: Bool {
        !model.isWorking && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSend else { return }
        commandsOpen = false
        let text = input
        input = ""
        Task { await model.submit(text) }
    }
}

/// L'opération soumise, telle que le serveur la décrit — la même carte que
/// dans le fil de discussion. Jamais « réussi » avant que le serveur le dise.
/// Une bulle : celle d'une conversation (couleurs du chat, queue, liseré) quand
/// Copilot est poussé depuis la liste ; celle des paiements dans la feuille.
private struct CopilotBubble: ViewModifier {
    let direction: MessageDirection
    let chatRoom: Bool

    func body(content: Content) -> some View {
        if chatRoom {
            content
                .background(ChatBubbleStyle.background(for: direction))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .applyStrokeOnBubbleView()
                .applyTailView(direction)
        } else {
            content.background(direction == .sent ? AppColors.primary : AppColors.cardBackground,
                               in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// « Fermer » dans une feuille ; rien dans la pile des discussions, où le
/// bouton retour du système suffit — comme dans une conversation.
private struct CopilotTaskControls: ViewModifier {
    let isPushed: Bool
    let isBusy: Bool
    let onClose: () -> Void

    func body(content: Content) -> some View {
        if isPushed {
            content
        } else {
            content.financeTaskControls(isBusy: isBusy, onClose: onClose)
        }
    }
}

/// Un texte qui s'écrit lettre à lettre, comme la réponse d'un assistant.
///
/// Le texte arrive entier — du serveur ou de l'app — : l'écriture n'est qu'un
/// effet, rapide (~35 lettres/s, 1,5 s au plus) et qu'un toucher achève. La
/// bulle a la taille du texte déjà écrit : elle s'élargit sur la première
/// ligne, puis grandit ligne à ligne. VoiceOver lit toujours la phrase entière.
struct CopilotTypingText: View {
    let text: String
    let animate: Bool
    var onProgress: () -> Void = {}
    let onFinished: () -> Void

    /// La première lettre paraît avec la bulle : jamais une bulle vide.
    @State private var shown = 1

    /// Environ 35 lettres par seconde.
    private static let tick: UInt64 = 28_000_000
    /// Au plus ~1,5 s : un long message s'écrit par groupes de lettres.
    private static let maxTicks = 54.0

    var body: some View {
        Text(text.prefix(animate ? shown : text.count))
            .accessibilityLabel(text)
            .contentShape(Rectangle())
            .onTapGesture { if animate { shown = text.count } }
            .task(id: animate) {
                guard animate else { return }
                let total = text.count
                let step = max(1, Int((Double(total) / Self.maxTicks).rounded(.up)))
                while shown < total {
                    try? await Task.sleep(nanoseconds: Self.tick)
                    // Quittée en cours d'écriture : le fil ne reste pas bloqué.
                    if Task.isCancelled { break }
                    shown = min(total, shown + step)
                    onProgress()
                }
                onFinished()
            }
    }
}

/// Un litige ouvert : son statut, sa catégorie, ses échéances et sa frise, lus
/// sur `GET /disputes/{id}` et `/timeline` — tels que le serveur les rend.
struct CopilotDisputeCard: View {
    let reference: FinancialReference
    let disputes: any DisputeFiling

    @State private var snapshot: DisputeStatusSnapshot?
    @State private var isRefreshing = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FinanceStrings.disputeTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            if let snapshot {
                row(FinanceStrings.copilotDisputeStatus, Self.label("status", snapshot.status))
                if let category = snapshot.category {
                    row(FinanceStrings.disputeReason, FinanceStrings.disputeCategoryLabel(category))
                }
                if let due = snapshot.firstResponseDueAt, snapshot.closedAt == nil {
                    row(FinanceStrings.copilotDisputeFirstResponse, due.formatted(date: .abbreviated, time: .shortened))
                }
                if let due = snapshot.resolveDueAt, snapshot.closedAt == nil {
                    row(FinanceStrings.copilotDisputeResolveBy, due.formatted(date: .abbreviated, time: .shortened))
                }
                ForEach(Array(snapshot.timeline.enumerated()), id: \.offset) { _, step in
                    row(Self.label("step", step.step), step.value ?? "")
                }
            } else {
                Text(FinanceStrings.receiptReference + " " + reference.id)
                    .font(.system(size: 13).monospaced())
                    .foregroundStyle(AppColors.subtitleGray)
                    .textSelection(.enabled)
            }
            if let failure {
                Text(failure).font(.system(size: 13)).foregroundStyle(AppColors.subtitleGray)
            }
            Button { Task { await refresh() } } label: {
                Label(FinanceStrings.flowCheckStatus, systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.primary)
            }
            .disabled(isRefreshing)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task { await refresh() }
        // Le litige s'ouvre ou se ferme côté serveur : la carte se relit (Q11).
        .onReceive(NotificationCenter.default.publisher(for: .financialDisputeChanged)) { _ in
            Task { await refresh() }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 14)).foregroundStyle(AppColors.subtitleGray)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Le mot du serveur, traduit quand l'app connaît sa clé — sinon lisible tel quel.
    static func label(_ kind: String, _ raw: String) -> String {
        FinanceLocalization.string("finance.dispute.\(kind).\(raw.lowercased())",
                                   fallback: raw.replacingOccurrences(of: "_", with: " ").capitalized)
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        switch await disputes.follow(disputeID: reference.id) {
        case .success(let fresh): snapshot = fresh; failure = nil
        case .failure(let error): failure = FinanceStrings.errorMessage(error)
        }
    }
}

struct CopilotOutcomeCard: View {
    let reference: FinancialReference
    let reader: (any FinancialObjectUseCasesProtocol)?
    var onReport: (() -> Void)? = nil
    var onRefund: (() -> Void)? = nil
    var onReverse: (() -> Void)? = nil
    /// Seulement dans une conversation : la carte du reçu s'y publie.
    var onShareReceipt: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    /// Seulement pour une demande d'argent : son lien de paiement.
    var onIssueLink: (() -> Void)? = nil

    @State private var payload: FinancialCardPayload?
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let payload {
                FinancialCardRegistry.view(for: payload)
            } else {
                Text(FinanceStrings.receiptReference + " " + reference.id)
                    .font(.system(size: 13).monospaced())
                    .foregroundStyle(AppColors.subtitleGray)
                    .textSelection(.enabled)
            }
            if reader != nil {
                Button {
                    Task { await refresh() }
                } label: {
                    // Comme le reçu : « vérifier le statut » — l'unique geste d'un
                    // utilisateur en doute (`intent/requery`), jamais un nouvel envoi.
                    Label(FinanceStrings.flowCheckStatus, systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                }
                .disabled(isRefreshing)
            }
            // Proposés seulement quand le serveur les autorise sur cette opération.
            if let onRefund, CopilotConversationViewModel.allowsRefundOrReversal(payload) {
                Button(action: onRefund) {
                    Label(FinanceStrings.copilotRequestRefund, systemImage: "arrow.uturn.backward.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                }
            }
            if let onReverse, CopilotConversationViewModel.allowsRefundOrReversal(payload) {
                Button(action: onReverse) {
                    Label(FinanceStrings.copilotRequestReversal, systemImage: "arrow.counterclockwise.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                }
            }
            if let onIssueLink {
                Button(action: onIssueLink) {
                    Label(FinanceStrings.copilotIssueLink, systemImage: "link")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                }
            }
            if let onCancel, CopilotConversationViewModel.allowsCancel(payload) {
                Button(action: onCancel) {
                    Label(FinanceStrings.actionsCancel, systemImage: "xmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                }
            }
            if let onShareReceipt, payload?.allowedActions?.contains("SHARE_RECEIPT") == true {
                Button(action: onShareReceipt) {
                    Label(FinanceStrings.copilotShareReceipt, systemImage: "doc.text")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                }
            }
            if let onReport, payload != nil, DisputeEligibility.allows(payload?.allowedActions) {
                Button(action: onReport) {
                    Label(FinanceStrings.copilotReportProblem, systemImage: "exclamationmark.bubble")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
        .task {
            if let reader { payload = await reader.current(for: reference) }
            await refresh()
        }
    }

    private func refresh() async {
        guard let reader, !isRefreshing else { return }
        isRefreshing = true
        if case .success(let fresh) = await reader.refresh(reference) { payload = fresh }
        isRefreshing = false
    }
}

/// La caméra, dans une carte du fil — le même aperçu que l'écran de scan.
///
/// L'autorisation se demande ici, au moment où l'on en a besoin. Refusée, la
/// carte le dit et renvoie aux Réglages ; elle ne scanne rien en douce.
struct CopilotQRScanCard: View {
    let onPayload: (String) -> Void

    @State private var permitted: Bool?

    var body: some View {
        Group {
            switch permitted {
            case true?:
                ZStack {
                    QRCameraPreview(onPayload: onPayload)
                    // Centré dans la carte, marges égales : le relevé de -50 du
                    // scanner plein écran sortirait la fenêtre par le haut.
                    QRScanReticle(side: 220, verticalOffset: 0)
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel(FinanceStrings.qrAimHint)
            case false?:
                VStack(spacing: 10) {
                    Text(FinanceStrings.qrCameraDenied)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.subtitleGray)
                        .multilineTextAlignment(.center)
                    Button(FinanceStrings.qrOpenSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.primary)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            case nil:
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:    permitted = true
            case .notDetermined: permitted = await AVCaptureDevice.requestAccess(for: .video)
            default:             permitted = false
            }
        }
    }
}
