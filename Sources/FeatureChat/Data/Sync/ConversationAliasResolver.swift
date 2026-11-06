//
//  ConversationAliasResolver.swift
//  FeatureChat
//
//  Follows a merged-away conversation to the one that replaced it.
//

import Foundation
import WaanguCoreKit

/// Redirects anything addressed to a conversation that has been merged away.
///
/// `ConversationDeduplicationService` keeps the losing row when the server
/// still lists it, pointing it at the survivor through `mergedIntoId`. That row
/// is never rendered — so every path that can still name it has to be sent on,
/// or the thread would quietly collect messages, unread counts and drafts that
/// nothing displays.
///
/// Four paths can still name it: the conversation sync, the per-conversation
/// message sync, an inbound message, and anything reading conversation state
/// by id.
enum ConversationAliasResolver {

    /// The conversation this row was merged into, or the row itself.
    ///
    /// Bounded rather than recursive: an alias is written pointing at a live
    /// row, but a cycle in stored data must not hang a sync.
    static func resolved(
        _ conversation: ConversationModel?,
        in database: any DatabaseRepositoryProtocol
    ) async -> ConversationModel? {
        var current = conversation
        var hops = 0

        while let mergedInto = current?.mergedIntoId, !mergedInto.isEmpty, hops < 4 {
            guard let next = try? await database.fetchOne(
                ConversationModel.self,
                id: mergedInto
            ) else { break }
            current = next
            hops += 1
        }

        return current
    }
}
