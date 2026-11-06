//
//  DiscussionDeduplicator.swift
//  FeatureChat
//
//  One row per person in the inbox, whatever the database holds.
//

import Foundation

/// Collapses inbox rows that are the same person, at read time.
///
/// `ConversationDeduplicationService` merges the underlying rows, but it cannot
/// merge every pair: a row the server still lists comes back on the next sync,
/// so deleting it locally would only make the merge undo itself every launch.
/// The list must be right regardless — so the fetch collapses what it finds,
/// and the user never sees the same person twice whether or not the merge could
/// touch those rows.
///
/// The winner is chosen with `ConversationDeduplicationService.survivor(among:)`
/// — the same rule the merge uses — so the row you tap before the merge runs is
/// the row the merge keeps, and the list does not reshuffle underneath you.
enum DiscussionDeduplicator {

    struct Row {
        let conversation: ConversationModel
        let item: DiscussionChatItem

        init(conversation: ConversationModel, item: DiscussionChatItem) {
            self.conversation = conversation
            self.item = item
        }
    }

    static func collapsed(_ rows: [Row]) -> [DiscussionChatItem] {
        PeerGrouping.groups(rows, identity: identity(of:))
            .map { $0.count == 1 ? $0[0].item : merged($0) }
    }

    /// Who the row is with — every identity it carries, not one of them.
    ///
    /// A group has no peer: it is identified by its own id, and two groups are
    /// never the same conversation however alike they look.
    static func identity(of row: Row) -> PeerIdentity {
        guard let contact = row.item.contact, !contact.isGroup else { return PeerIdentity() }
        return PeerIdentity(userId: contact.userId, phone: contact.phone)
    }

    private static func merged(_ group: [Row]) -> DiscussionChatItem {
        let conversations = group.map(\.conversation)
        let winner = ConversationDeduplicationService.survivor(among: conversations)
        var item = group.first { $0.conversation.id == winner?.id }?.item ?? group[0].item

        // Unread counts are disjoint — each row holds different messages — so
        // the number of messages waiting from this person is their sum, not the
        // larger of the two.
        item.count = group.reduce(0) { $0 + $1.item.count }

        // The newest thing this person said, wherever it is stored. Showing the
        // winner's own last message would age the row backwards whenever the
        // duplicate is the livelier half.
        if let newest = group.map(\.item.lastMessage).max(by: { $0.createdAt < $1.createdAt }),
           newest.createdAt > item.lastMessage.createdAt {
            item.lastMessage = newest
        }

        // A name beats no name: one of the two rows may never have learned who
        // it was with.
        if item.contact?.userName.isEmpty ?? true,
           let named = group.compactMap(\.item.contact).first(where: { !$0.userName.isEmpty }) {
            item.contact = named
        }

        // Never lose an unsent draft to the row that lost.
        if item.draft?.isEmpty ?? true,
           let draft = group.compactMap(\.item.draft).first(where: { !$0.isEmpty }) {
            item.draft = draft
        }

        return item
    }
}
