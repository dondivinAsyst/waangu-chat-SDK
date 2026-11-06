//
//  DirectConversationLookup.swift
//  FeatureChat
//
//  Finds the conversation we already have with a person.
//

import Foundation
import WaanguCoreKit

/// Finds an existing one-to-one conversation by who it is with.
///
/// Both writers that can create a conversation — the conversation sync and an
/// inbound message — decide "do we have this already?" from an id the server
/// chose. A chat started on this device has no such id until an ACK links one,
/// so both writers used to answer "no" and create a second row for a person
/// already in the inbox. Asking by peer instead is what closes that.
///
/// Restricted to rows with no `serverId`: a row already linked to a *different*
/// server conversation is a different conversation as far as the backend is
/// concerned, and folding this one into it would rewrite that thread's identity.
/// Those are handled after the fact, by merging.
enum DirectConversationLookup {

    static func unlinked(
        peerUserId: String,
        phone: String? = nil,
        in database: any DatabaseRepositoryProtocol
    ) async -> ConversationModel? {
        var candidateIds: [String] = []

        if !peerUserId.isEmpty {
            candidateIds += await participantConversationIds(
                matching: FilterSpec("user_id == %@", .string(peerUserId)),
                in: database
            )
        }

        if candidateIds.isEmpty, let phone, !phone.isEmpty {
            candidateIds += await participantConversationIds(
                matching: FilterSpec("phone == %@", .string(phone)),
                in: database
            )
        }

        for id in candidateIds {
            guard let conversation = try? await database.fetchOne(ConversationModel.self, id: id),
                  conversation.type == .direct,
                  conversation.serverId == nil,
                  conversation.mergedIntoId == nil
            else { continue }
            return conversation
        }

        return nil
    }

    private static func participantConversationIds(
        matching filter: FilterSpec,
        in database: any DatabaseRepositoryProtocol
    ) async -> [String] {
        let participants = try? await database.fetch(
            ConversationParticipantModel.self,
            query: QuerySpec(filter: filter, limit: 20)
        )
        return participants?.map(\.conversationId) ?? []
    }
}
