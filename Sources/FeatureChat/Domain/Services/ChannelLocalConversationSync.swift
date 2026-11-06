//
//  ChannelLocalConversationSync.swift
//  FeatureChat
//

import Foundation

/// Makes sure a followed channel has a local conversation row, without ever
/// touching one that is already there.
///
/// Before this, a channel only got persisted the first time its room was
/// opened (`ChannelRoomViewModel.ensureLocalConversation`) — so a channel this
/// device follows but has never opened stayed invisible everywhere that reads
/// the local inbox instead of Identity, and a broadcast landing on it before
/// the room was ever opened had no row to attach to. This is the same write
/// `ensureLocalConversation` used to do alone, now shared so the channel list
/// can run it for everything it just fetched, not only the one room a reader
/// happens to open.
enum ChannelLocalConversationSync {

    /// Ensures a row for every channel that has a conversation and is not
    /// already persisted. Fetches the existing rows once and diffs against
    /// them, so following N channels costs one read plus one write per
    /// channel actually missing — not a lookup per channel.
    static func ensureAll(
        _ channels: [Channel],
        discussionUseCases: DiscussionUseCasesProtocol
    ) async {
        let existingConversationIds = Set(
            ((try? await discussionUseCases.getDiscussions.execute()) ?? [])
                .map(\.conversationId)
        )

        for channel in channels {
            guard let conversationId = channel.conversationId, !conversationId.isEmpty,
                  !existingConversationIds.contains(conversationId) else { continue }

            await create(conversationId: conversationId, channel: channel, discussionUseCases: discussionUseCases)
        }
    }

    /// Ensures a row for one channel. Re-checks for an existing row itself —
    /// safe to call on its own, as `ChannelRoomViewModel` does, without going
    /// through `ensureAll`'s batch read first.
    static func ensure(
        conversationId: String,
        channel: Channel,
        discussionUseCases: DiscussionUseCasesProtocol
    ) async {
        let existing = try? await discussionUseCases.getDiscussions.execute()?
            .first { $0.conversationId == conversationId }
        guard existing == nil else { return }

        await create(conversationId: conversationId, channel: channel, discussionUseCases: discussionUseCases)
    }

    private static func create(
        conversationId: String,
        channel: Channel,
        discussionUseCases: DiscussionUseCasesProtocol
    ) async {
        let placeholder = MessageDataItem(
            codeMessage: "",
            senderId: "",
            groupId: conversationId,
            typeMessage: .TEXT,
            message: MessageContent(text: ""),
            status: .SEEN,
            createdAt: channel.createdAt ?? Date()
        )

        let conversation = DiscussionChatItem(
            lastMessage: placeholder,
            conversationId: conversationId,
            contact: ContactChannel(
                userName: channel.name,
                phone: "",
                image: channel.image,
                isBlocked: false,
                // Stored as `.channel`, not `.group`: the mapper reads
                // `isChannel` to pick the type, and the inbox needs it to tell a
                // broadcast from a group when the sync catches up.
                isGroup: true,
                isChannel: true,
                id: conversationId
            )
        )

        try? await discussionUseCases.createDiscussion.execute(discussion: conversation)
    }
}
