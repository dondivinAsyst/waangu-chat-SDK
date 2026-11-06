//
//  PublishFinanceMessageUseCase.swift
//  FeatureChat
//
//  Annonce d'une opération financière déjà soumise, sous forme de message.
//

import Foundation
import WaanguCoreKit

// MARK: - Cible

/// La conversation où une opération financière s'annonce.
///
/// Tout ce que la publication doit savoir, et rien de ce qu'un écran détient :
/// la conversation ouverte en fournissait autrefois les morceaux un par un, ce
/// qui rendait l'annonce impossible hors d'un fil — d'où la redirection que
/// faisaient les Réglages *avant* le paiement.
public struct FinanceMessageTarget: Equatable {

    /// Identifiant du fil. Pour une première conversation, c'est celui que
    /// l'appelant a fabriqué : le même doit ensuite servir à ouvrir le fil,
    /// sans quoi le message atterrit dans une conversation que l'écran ne
    /// montre pas.
    public let conversationId: String
    public let kind: ConversationKind
    /// Destinataire du message. Vide en groupe, où le fil désigne les membres.
    public let receiverUserId: String
    /// Contact de la discussion à créer si le fil n'existe pas encore.
    public let contact: ContactChannel

    public init(
        conversationId: String,
        kind: ConversationKind,
        receiverUserId: String,
        contact: ContactChannel
    ) {
        self.conversationId = conversationId
        self.kind = kind
        self.receiverUserId = receiverUserId
        self.contact = contact
    }
}

// MARK: - Erreurs

public enum PublishFinanceMessageError: Error, Equatable {
    /// Aucun identifiant de fil : rien où publier.
    case missingConversation
    /// L'historique du fil n'a pas pu être lu, ou la discussion pas créée.
    case storageFailed(String)
}

// MARK: - Contrat

public protocol PublishFinanceMessageUseCaseProtocol: AnyObject {

    /// Publie `reference` dans `target` comme un message ordinaire.
    ///
    /// Suit exactement le chemin d'un message : discussion créée si elle
    /// n'existe pas, puis outbox et publication. **N'exécute jamais
    /// l'opération** et ne la rejoue pas : elle est déjà soumise.
    ///
    /// - Parameter onLocallySaved: appelé avec chaque version du message dès
    ///   qu'elle est enregistrée — d'abord la carte en attente, puis la carte
    ///   enrichie par le serveur. Un fil ouvert s'en sert pour l'afficher sans
    ///   attendre l'observation de la base ; hors fil, on peut l'ignorer.
    /// - Returns: le message publié, dans sa dernière version connue.
    /// - Parameter note: motif saisi par l'émetteur, publié comme le texte du
    ///   message. `nil` pour les parcours qui n'en proposent pas.
    @discardableResult
    func execute(
        _ reference: FinancialReference,
        note: String?,
        to target: FinanceMessageTarget,
        onLocallySaved: (([MessageDataItem]) async -> Void)?
    ) async throws -> MessageDataItem
}

public extension PublishFinanceMessageUseCaseProtocol {

    @discardableResult
    func execute(
        _ reference: FinancialReference,
        to target: FinanceMessageTarget,
        onLocallySaved: (([MessageDataItem]) async -> Void)?
    ) async throws -> MessageDataItem {
        try await execute(reference, note: nil, to: target, onLocallySaved: onLocallySaved)
    }
}

// MARK: - Implémentation

/// Acteur : deux demandes pour la même référence — double tap, retour de
/// Réglages pendant une publication — doivent partager un seul envoi, et ce
/// partage demande un état.
actor PublishFinanceMessageUseCase: PublishFinanceMessageUseCaseProtocol {

    private let discussions: any DiscussionUseCasesProtocol
    private let messages: any MessagesUseCasesProtocol
    private let publishOutgoing: any PublishOutgoingMessageUseCaseProtocol
    private let objects: any FinancialObjectUseCasesProtocol
    private let currentUserId: @Sendable () -> String

    private var inFlight: [String: Task<MessageDataItem, Error>] = [:]

    init(
        discussions: any DiscussionUseCasesProtocol,
        messages: any MessagesUseCasesProtocol,
        publishOutgoing: any PublishOutgoingMessageUseCaseProtocol,
        objects: any FinancialObjectUseCasesProtocol,
        currentUserId: @escaping @Sendable () -> String
    ) {
        self.discussions = discussions
        self.messages = messages
        self.publishOutgoing = publishOutgoing
        self.objects = objects
        self.currentUserId = currentUserId
    }

    func execute(
        _ reference: FinancialReference,
        note: String?,
        to target: FinanceMessageTarget,
        onLocallySaved: (([MessageDataItem]) async -> Void)?
    ) async throws -> MessageDataItem {
        guard !target.conversationId.isEmpty else {
            throw PublishFinanceMessageError.missingConversation
        }

        let key = "\(target.conversationId):\(reference.id)"
        if let pending = inFlight[key] { return try await pending.value }

        let task = Task { try await publish(reference, note: note, to: target, onLocallySaved: onLocallySaved) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    private func publish(
        _ reference: FinancialReference,
        note: String?,
        to target: FinanceMessageTarget,
        onLocallySaved: (([MessageDataItem]) async -> Void)?
    ) async throws -> MessageDataItem {
        let conversationId = target.conversationId
        let history: [MessageDataItem]
        do {
            history = try await discussions.getMessages.execute(conversationId: conversationId) ?? []
        } catch {
            throw PublishFinanceMessageError.storageFailed(String(describing: error))
        }

        // Déjà annoncée : une annonce restée en attente est republiée, jamais
        // dupliquée.
        let me = currentUserId()
        if var existing = history.first(where: {
            $0.senderId == me && $0.transactionId == reference.id
        }) {
            if existing.status == .PENDING {
                // Restée en attente sans carte : elle repart complète si le
                // serveur répond maintenant — voir `publishablePayload`.
                if existing.message.financial == nil,
                   let payload = await publishablePayload(for: reference) {
                    existing.message.financial = payload
                    _ = try? await messages.updateMessages.execute(message: existing)
                }
                await publishOutgoing.execute(message: existing, conversationId: conversationId)
            }
            return existing
        }

        // Aucun montant de brouillon ni révision inventée : la carte part de
        // l'état connu du magasin, sinon de l'état lu au serveur **avant** la
        // publication, sinon en simple référence.
        var current = await objects.current(for: reference)
        let readBeforePublishing = current == nil
        if readBeforePublishing {
            current = await publishablePayload(for: reference)
        }
        let message = FinanceConversationMessage.make(
            reference: reference,
            note: note,
            payload: current,
            groupID: target.kind.travelsAsGroup ? conversationId : nil,
            receiverID: target.receiverUserId
        )

        // Le chemin d'une première conversation, inchangé : la discussion
        // naît du premier message.
        let discussion = DiscussionChatItem(
            lastMessage: message,
            conversationId: conversationId,
            contact: target.contact
        )
        do {
            try await discussions.createDiscussion.execute(discussion: discussion)
        } catch {
            throw PublishFinanceMessageError.storageFailed(String(describing: error))
        }
        await onLocallySaved?([message])
        await MainActor.run {
            NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
        }
        await publishOutgoing.execute(message: message, conversationId: conversationId)

        // Déjà lu juste avant : une seconde lecture n'apprendrait rien.
        if readBeforePublishing { return message }

        // Enrichissement par la seule projection serveur, sous garde de version.
        // Un échec ici n'annule rien : le message est publié, sa carte reste en
        // attente et la réconciliation la complétera.
        guard case .success(let payload) = await objects.refresh(reference),
              let latest = try? await discussions.getMessages.execute(conversationId: conversationId),
              var saved = latest.first(where: { $0.codeMessage == message.codeMessage })
        else { return message }

        saved.message.financial = payload
        // `saved` vient de la base : l'ACK ou la lecture arrivés pendant la
        // lecture serveur y sont déjà, et ne sont pas écrasés.
        guard (try? await messages.updateMessages.execute(message: saved)) != nil else {
            return message
        }
        await onLocallySaved?([saved])
        return saved
    }

    /// L'état serveur de l'objet, lu par son propriétaire avant publication.
    ///
    /// **La charge publiée est tout ce que le destinataire aura.** Il ne peut
    /// pas relire l'objet (`reasonForAccess=SELF` est réservé au propriétaire) :
    /// publier la seule référence le laissait sur « Chargement des détails… »,
    /// et la lecture faite après publication n'enrichissait que la copie de
    /// l'expéditeur. L'expéditeur, lui, a le droit de lire — il lit donc avant.
    ///
    /// `nil` si la lecture échoue : le message part quand même, en référence.
    private func publishablePayload(for reference: FinancialReference) async -> FinancialCardPayload? {
        guard case .success(let payload) = await objects.refresh(reference) else { return nil }
        return payload
    }
}
