//
//  ShareSplitBillUseCase.swift
//  FeatureChat
//
//  Un partage créé s'annonce dans la conversation de chaque participant.
//

import Foundation
import WaanguCoreKit

/// Le compte rendu d'une diffusion : qui a reçu le partage, et qui non.
public struct SplitBillShareReport: Equatable, Sendable {
    /// Identifiants des participants dont le fil porte désormais le partage.
    public let sharedWith: [String]
    /// Identifiants des participants pour qui l'annonce a échoué.
    public let failed: [String]

    public var isComplete: Bool { failed.isEmpty }
}

public protocol ShareSplitBillUseCaseProtocol: Sendable {

    /// Les contacts qu'on peut inviter : ceux avec qui l'on peut échanger.
    ///
    /// Ici plutôt que dans l'écran, parce que c'est la même règle que la
    /// diffusion : un participant qu'on ne pourrait pas joindre dans un fil ne
    /// verrait jamais le partage.
    func participantCandidates() async -> [UserContactProps]

    /// Annonce `split` dans la conversation individuelle de chaque participant —
    /// celle qui existe, ou une première conversation.
    ///
    /// N'échoue pas en bloc : un participant injoignable n'empêche pas les
    /// autres de recevoir le partage. Le partage lui-même est **déjà créé**
    /// au serveur ; rien ici ne le recrée.
    func share(
        _ split: SplitBill,
        correlationID: CorrelationId,
        with participants: [UserContactProps]
    ) async -> SplitBillShareReport
}

actor ShareSplitBillUseCase: ShareSplitBillUseCaseProtocol {

    private let contacts: any ContactsUseCasesProtocol
    private let lookup: DirectDiscussionFinder
    private let publisher: any PublishFinanceMessageUseCaseProtocol
    private let currentUserId: @Sendable () -> String
    private let makeConversationId: @Sendable () -> String

    init(
        contacts: any ContactsUseCasesProtocol,
        discussions: any DiscussionUseCasesProtocol,
        publisher: any PublishFinanceMessageUseCaseProtocol,
        currentUserId: @escaping @Sendable () -> String,
        makeConversationId: @escaping @Sendable () -> String = { UUID().lowercasedString }
    ) {
        self.contacts = contacts
        self.lookup = DirectDiscussionFinder(discussions: discussions)
        self.publisher = publisher
        self.currentUserId = currentUserId
        self.makeConversationId = makeConversationId
    }

    func participantCandidates() async -> [UserContactProps] {
        do {
            let result = try await contacts.getPersistedContacts.execute()
            let me = currentUserId()
            // Soi-même n'est pas un participant qu'on invite : l'organisateur
            // est porté par le partage.
            return (result?.UserContactProps ?? []).filter {
                !$0.isBlocked && $0.userId != me && !$0.userId.isEmpty
            }
        } catch {
            await AppLogger.shared.log("Split participants load failed: \(error)", level: .warning)
            return []
        }
    }

    func share(
        _ split: SplitBill,
        correlationID: CorrelationId,
        with participants: [UserContactProps]
    ) async -> SplitBillShareReport {
        // Version 0 : le partage vient d'être créé et sa révision appartient au
        // backend. La première lecture authentique remplace cet écho sans
        // condition — même règle que pour un devis.
        let reference = FinancialReference(
            type: .splitBill,
            id: split.id,
            version: 0,
            correlationID: correlationID
        )

        var shared: [String] = []
        var failed: [String] = []

        // Un par un, pas en parallèle : chaque annonce crée au besoin une
        // discussion, et des créations concurrentes sur la même base se
        // disputeraient la ligne de liste.
        for participant in participants where participant.userId != currentUserId() {
            do {
                let existing = try await lookup.conversationId(forPhone: participant.phone)
                let target = FinanceMessageTarget(
                    conversationId: existing ?? makeConversationId(),
                    kind: .direct,
                    receiverUserId: participant.userId,
                    contact: .direct(participant)
                )
                try await publisher.execute(reference, to: target, onLocallySaved: nil)
                shared.append(participant.userId)
            } catch {
                failed.append(participant.userId)
                await AppLogger.shared.log(
                    "Split share failed split=\(split.id) participant=\(participant.userId): \(error)",
                    level: .error
                )
            }
        }
        return SplitBillShareReport(sharedWith: shared, failed: failed)
    }
}
