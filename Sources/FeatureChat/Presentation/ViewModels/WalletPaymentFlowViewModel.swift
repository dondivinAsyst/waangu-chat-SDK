//
//  WalletPaymentFlowViewModel.swift
//  FeatureChat
//
//  Envoi et demande d'argent lancés depuis le portefeuille des Réglages.
//

import Foundation
import WaanguCoreKit

/// Le parcours « bénéficiaire → opération → conversation » hors d'un fil.
///
/// **Rien ne navigue avant l'opération.** Choisir quelqu'un ne l'ouvre pas : on
/// retient seulement le fil qui existe déjà avec lui, s'il existe. L'opération
/// se fait en feuille, s'annonce ensuite comme un message ordinaire — ce qui
/// crée la conversation si elle manquait, par le chemin d'un premier message —
/// et c'est seulement au retour que le fil s'ouvre, pour montrer ce message.
///
/// Autrefois le choix du contact basculait aussitôt vers la conversation : un
/// utilisateur qui renonçait se retrouvait dans un fil qu'il n'avait pas voulu
/// ouvrir.
@MainActor
final class WalletPaymentFlowViewModel: ObservableObject {

    /// La feuille du parcours. **Une seule**, du choix du bénéficiaire jusqu'au
    /// reçu : son contenu passe du sélecteur au formulaire sans qu'elle se
    /// ferme. Deux feuilles enchaînées — l'une qui se ferme pendant que l'autre
    /// s'ouvre — échouent en SwiftUI, et la seconde ne s'affiche jamais.
    @Published var sheet: FlowSheet?

    struct FlowSheet: Identifiable {
        let entry: FinanceCatalogEntry
        /// `nil` tant que le bénéficiaire n'est pas choisi.
        var payment: PresentedPayment?
        /// Stable pendant tout le parcours : la feuille ne se recrée pas quand
        /// le contenu change.
        var id: String { entry.id }
    }

    struct PresentedPayment {
        let recipientInput: RecipientInput
        let recipientName: String?
        /// `nil` pour un bénéficiaire désigné par QR : sans identité de
        /// messagerie, il n'y a aucun fil où annoncer l'opération.
        let recipient: Recipient?
    }

    /// Le bénéficiaire tel que la messagerie le connaît.
    struct Recipient {
        let phone: String
        let userId: String
        let contact: ContactChannel
        /// Fil existant au moment du choix. `nil` n'est pas un échec : c'est
        /// une première conversation, qui naîtra de l'annonce.
        let existingConversationId: String?
        /// Le fil de l'opération : l'existant, ou un nouvel identifiant fabriqué
        /// au choix — comme au démarrage d'une conversation. Le prepare le porte
        /// (`send-money/prepare` l'exige), et l'annonce y fait naître le fil.
        let conversationId: String
    }

    private let lookup: DirectDiscussionFinder
    private let publisher: any PublishFinanceMessageUseCaseProtocol
    private let makeConversationId: () -> String

    /// Fil où l'opération a été annoncée — le seul à ouvrir ensuite.
    ///
    /// Pour une première conversation, c'est l'identifiant fabriqué à
    /// l'annonce. Ouvrir le fil sans lui ferait fabriquer un second
    /// identifiant par l'écran de conversation, et le message atterrirait
    /// dans un fil que l'écran ne montre pas.
    ///
    /// Tenu hors de `sheet` : la feuille est déjà fermée quand on le lit.
    private var published: (recipient: Recipient, conversationId: String)?

    /// Les natures qui exigent un bénéficiaire avant d'ouvrir quoi que ce soit.
    static let needsRecipient: Set<FinanceEntryKind> = [.sendMoney, .requestMoney]

    init(
        discussions: any DiscussionUseCasesProtocol,
        publisher: any PublishFinanceMessageUseCaseProtocol,
        makeConversationId: @escaping () -> String = { UUID().lowercasedString }
    ) {
        self.lookup = DirectDiscussionFinder(discussions: discussions)
        self.publisher = publisher
        self.makeConversationId = makeConversationId
    }

    // MARK: - Choix

    /// `true` si l'entrée passe par ce parcours ; sinon l'appelant l'ouvre
    /// lui-même.
    func begin(_ entry: FinanceCatalogEntry) -> Bool {
        guard Self.needsRecipient.contains(entry.kind) else { return false }
        published = nil
        sheet = FlowSheet(entry: entry, payment: nil)
        return true
    }

    /// Contact choisi : le fil existant est retenu, rien n'est ouvert.
    func picked(_ contact: UserContactProps) async {
        guard sheet != nil else { return }
        let recipient = await recipient(for: contact)
        // Relu après l'attente : l'utilisateur a pu fermer la feuille entre-temps.
        guard sheet != nil else { return }
        sheet?.payment = PresentedPayment(
            recipientInput: .phoneNumber(contact.phone),
            recipientName: contact.name,
            recipient: recipient
        )
    }

    /// Le bénéficiaire d'un contact, avec son fil existant s'il y en a un.
    /// Sans feuille : Waangu Copilot s'en sert aussi.
    func recipient(for contact: UserContactProps) async -> Recipient {
        let existing = await existingConversationId(forUserId: contact.userId, phone: contact.phone)
        return Recipient(
            phone: contact.phone,
            userId: contact.userId,
            contact: .direct(contact),
            existingConversationId: existing,
            conversationId: existing ?? makeConversationId()
        )
    }

    /// Bénéficiaire venu d'un QR : l'opération se fait, sans fil où s'annoncer.
    func pickedWalletHandle(_ input: RecipientInput) {
        sheet?.payment = PresentedPayment(recipientInput: input, recipientName: nil, recipient: nil)
    }

    // MARK: - Annonce

    /// Annonce la référence produite, dans le fil existant ou dans une
    /// première conversation. Branché sur `financePublishReference`.
    /// - Parameter note: motif saisi par l'émetteur, publié comme texte du message.
    func publish(_ reference: FinancialReference, note: String? = nil) async -> Bool {
        guard let recipient = sheet?.payment?.recipient else { return false }
        return await publish(reference, note: note, to: recipient)
    }

    /// Annonce chez `recipient`, sans feuille — Waangu Copilot. Le fil d'une
    /// annonce précédente au même bénéficiaire est repris : une nouvelle
    /// tentative ne crée jamais un second fil.
    func publish(_ reference: FinancialReference, note: String? = nil, to recipient: Recipient) async -> Bool {
        let conversationId = (published?.recipient.userId == recipient.userId ? published?.conversationId : nil)
            ?? recipient.conversationId
        let target = FinanceMessageTarget(
            conversationId: conversationId,
            kind: .direct,
            receiverUserId: recipient.userId,
            contact: recipient.contact
        )
        do {
            try await publisher.execute(reference, note: note, to: target, onLocallySaved: nil)
            // Retenu même si la carte n'a pas pu s'enrichir : le message existe,
            // et une nouvelle tentative doit viser le même fil.
            published = (recipient, conversationId)
            return true
        } catch {
            await AppLogger.shared.log(
                "Wallet finance publication failed ref=\(reference.id): \(error)",
                level: .error
            )
            return false
        }
    }

    // MARK: - Fin

    /// Ferme la feuille — bouton de retour du reçu, ou annulation.
    func close() {
        sheet = nil
    }

    /// À appeler une fois la feuille **fermée**, quelle qu'en soit la raison.
    ///
    /// Rend le fil à ouvrir si l'opération y a été annoncée ; `nil` si
    /// l'utilisateur a renoncé, ou pour un QR. Naviguer avant la fin de la
    /// fermeture ferait basculer d'onglet sous une feuille encore visible.
    func conversationToOpen() -> ConversationType? {
        defer { published = nil }
        guard let published else { return nil }
        let recipient = published.recipient
        return .direct(
            phoneNumber: recipient.phone,
            conversationId: published.conversationId,
            peer: DirectChatPeer(
                userId: recipient.userId,
                idContact: recipient.contact.id,
                name: recipient.contact.userName,
                avatar: recipient.contact.image ?? ""
            )
        )
    }

    // MARK: - Privé

    /// Même rapprochement que l'écran de conversation.
    private func existingConversationId(forUserId userId: String, phone: String) async -> String? {
        do {
            return try await lookup.conversationId(forUserId: userId, phone: phone)
        } catch {
            // Lecture ratée : on le journalise plutôt que de le taire. L'annonce
            // fabriquera un identifiant, comme pour une première conversation.
            await AppLogger.shared.log(
                "Wallet finance: discussions lookup failed: \(error)",
                level: .warning
            )
            return nil
        }
    }
}
