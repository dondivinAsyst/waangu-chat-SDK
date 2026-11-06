//
//  WalletHomeView.swift
//  FeatureChat
//
//  L'accueil financier sous sa forme plein écran, depuis les Réglages.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// L'hôte du portefeuille atteint depuis les Réglages.
///
/// **N'a pas de page à lui.** La page est ``FinanceHomeView``, la même que celle
/// de l'onglet Waangu d'une conversation ; cet écran n'apporte que ce qui lui
/// est propre : sa barre de titre, son scanner, et le fait qu'il n'y a ici
/// personne en face — les parcours qui exigent un bénéficiaire passent donc
/// d'abord par un choix de contact.
struct WalletHomeView: View {

    let surface: ChatFinanceSurface
    let contacts: any ContactsUseCasesProtocol
    let translationService: (any TranslationServiceProtocol)?

    /// Ouvre le fil où une opération vient d'être annoncée.
    ///
    /// Appelé **après** l'opération, jamais avant : le fil s'ouvre pour montrer
    /// le message, en attente ou envoyé.
    let onOpenConversation: (ConversationType) -> Void
    let onBack: () -> Void
    /// La conversation Copilot conservée — la même que dans la liste des discussions.
    let copilotStore: (any CopilotConversationStoring)?

    @StateObject private var flow: WalletPaymentFlowViewModel
    @State private var presentedEntry: FinanceCatalogEntry?
    /// Le dossier personnel du serveur — `GET /financial/self-conversation`.
    ///
    /// Résolu ici, une fois : c'est la conversation de tout ce que cet écran
    /// ouvre, et `PaymentsDestination` n'a plus à la redemander parcours par
    /// parcours.
    @State private var selfFolderID = ""

    init(
        surface: ChatFinanceSurface,
        contacts: any ContactsUseCasesProtocol,
        discussions: any DiscussionUseCasesProtocol,
        publisher: any PublishFinanceMessageUseCaseProtocol,
        translationService: (any TranslationServiceProtocol)?,
        onOpenConversation: @escaping (ConversationType) -> Void,
        onBack: @escaping () -> Void,
        copilotStore: (any CopilotConversationStoring)? = nil
    ) {
        self.copilotStore = copilotStore
        self.surface = surface
        self.contacts = contacts
        self.translationService = translationService
        self.onOpenConversation = onOpenConversation
        self.onBack = onBack
        _flow = StateObject(wrappedValue: WalletPaymentFlowViewModel(
            discussions: discussions,
            publisher: publisher
        ))
    }

    // MARK: - Corps

    var body: some View {
        VStack(spacing: 0) {
            // Pas de bouton QR en barre de titre : la pastille « Scan » de
            // l'accueil ouvre déjà le scanner. Deux commandes pour un seul geste
            // font chercher la différence entre elles — il n'y en a pas.
            WalletNavigationBar(title: title, onBack: onBack) { EmptyView() }

            FinanceHomeView(
                surface: surface,
                context: hubContext,
                onSelect: select,
                translationService: translationService,
                // Copilot paie un contact comme l'écran d'envoi : son fil, puis l'annonce,
                // et le fil s'ouvre à la fermeture.
                copilotMessaging: flow,
                onCopilotClosed: openAnnouncedConversation,
                copilotStore: copilotStore
            )
        }
        .background(AppColors.walletCanvas)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarHidden(true)
        .task {
            guard selfFolderID.isEmpty else { return }
            selfFolderID = await surface.catalog.personalFolder()?.conversationID ?? ""
        }
        // Envoi et demande : bénéficiaire puis formulaire, **dans une même
        // feuille**. Le portefeuille reste dessous ; rien ne navigue tant que
        // l'opération n'est pas annoncée.
        //
        // Variante qui reporte l'apparence choisie dans l'application : une
        // feuille n'hérite pas du `preferredColorScheme` de l'écran qui la
        // présente, et le sélecteur comme l'alerte d'abandon restaient clairs
        // en mode sombre.
        .chatAppearanceSheet(item: $flow.sheet, onDismiss: openAnnouncedConversation) { sheet in
            if let payment = sheet.payment {
                PaymentsDestination(
                    entry: sheet.entry,
                    surface: surface,
                    // Le fil n'est connu qu'à l'annonce — il peut ne pas exister
                    // encore. Les formulaires n'en ont pas besoin pour opérer.
                    // Le fil existant, ou l'identifiant d'un nouveau fil, fabriqué
                    // au choix : le prepare d'un envoi l'exige, et l'annonce y
                    // fait naître la conversation. Vide pour un QR, sans fil.
                    conversationID: payment.recipient?.conversationId ?? "",
                    recipientInput: payment.recipientInput,
                    recipientName: payment.recipientName,
                    publishReference: publication(for: payment),
                    onDismiss: { flow.close() }
                )
            } else {
                FinanceRecipientPicker(
                    contacts: contacts,
                    qrResolver: surface.qrResolver,
                    translationService: translationService,
                    onPickedContact: { contact in
                        Task { await flow.picked(contact) }
                    },
                    onPickedWalletHandle: { flow.pickedWalletHandle($0) },
                    onDismiss: { flow.close() }
                )
            }
        }
        // Les autres parcours s'ouvrent en feuille, **avec leur propre pile**.
        //
        // Ils étaient poussés sur la pile des Réglages. Celle-ci est liée au
        // `NavigationPath` du coordinateur, alors que les parcours poussent
        // leurs écrans suivants par `navigationDestination(isPresented:)`, que
        // ce chemin ne connaît pas. Un niveau tenait ; le second — « + » d'un
        // partage, un partage de la liste, le paiement après un scan — faisait
        // reconstruire la pile depuis le chemin, et l'utilisateur se retrouvait
        // sur les Réglages.
        //
        // Dans leur propre pile, ces parcours se comportent exactement comme
        // depuis une conversation, où ils fonctionnent déjà : même
        // `FinanceNavigationScope` autour de la même table.
        .chatAppearanceSheet(item: $presentedEntry) { entry in
            FinanceNavigationScope {
                // La **même** table que la conversation. Sans bénéficiaire, pas
                // de fil où publier une référence, d'où `publishReference` absent.
                PaymentsDestination(
                    entry: entry,
                    surface: surface,
                    // Le dossier personnel porte l'opération : facture,
                    // recharge, dépôt et retrait s'y rattachent (§5.1.1).
                    conversationID: selfFolderID,
                    onDismiss: { presentedEntry = nil }
                )
            }
            .environment(\.financeFlowSurface, surface)

            .environment(\.financeOperationKeys, surface.operationKeys)
        }
    }

    // MARK: - Sélection

    private func select(_ entry: FinanceCatalogEntry) {
        if !flow.begin(entry) {
            presentedEntry = entry
        }
    }

    /// Annonce dans le fil du bénéficiaire. `nil` pour un QR : sans identité
    /// de messagerie, il n'y a pas de fil, et non « une publication qui échoue ».
    private func publication(
        for payment: WalletPaymentFlowViewModel.PresentedPayment
    ) -> (@MainActor (FinancialReference, String?) async -> Bool)? {
        guard payment.recipient != nil else { return nil }
        return { [flow] reference, note in await flow.publish(reference, note: note) }
    }

    /// La feuille est fermée : le fil s'ouvre si l'opération y a été annoncée.
    private func openAnnouncedConversation() {
        if let conversation = flow.conversationToOpen() {
            onOpenConversation(conversation)
        }
    }

    // MARK: - Contexte

    /// Le portefeuille **est** le dossier personnel (§5.1.1).
    ///
    /// Une vraie conversation, avec son identifiant, son titre et son époque
    /// d'appartenance — pas une absence de conversation. Ce contexte disait
    /// pourtant deux choses fausses à la fois : un identifiant vide, alors que
    /// le serveur en rend un, et une nature de tête-à-tête, alors qu'il n'y a
    /// personne en face.
    ///
    /// Conséquence assumée : interrogé sur `SELF`, le Hub ne propose que les
    /// quatre parcours du groupe `WALLET` — facture, recharge, dépôt, retrait.
    /// Envoyer, Demander et Scanner ne s'y affichent plus, et c'est juste : ils
    /// s'adressent à quelqu'un, et se font depuis une conversation. Les garder
    /// exigeait de mentir au serveur sur ce qu'est cet écran.
    ///
    /// Identifiant vide tant que le dossier n'a pas répondu : le Hub ne lit que
    /// le type, et les parcours attendent la résolution avant de préparer quoi
    /// que ce soit.
    private var hubContext: ChatFinanceContext {
        ChatFinanceContext(conversationID: selfFolderID,
                           conversationKind: .selfChat,
                           participantCount: 1)
    }

    private var title: String {
        FinanceLocalization.string("wallet_title", fallback: "Mon portefeuille")
    }
}
