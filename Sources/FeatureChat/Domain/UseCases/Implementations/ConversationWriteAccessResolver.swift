//
//  ConversationWriteAccessResolver.swift
//  FeatureChat
//

import Foundation

/// Resolves a room's write rule from the two places that hold one: the channel
/// registry and the community a group belongs to.
///
/// Both lookups run against data this device already has, so a room opens at
/// normal speed and a failure to answer leaves the room unrestricted — locking
/// a plain group chat because a listing timed out would be far worse than
/// showing a composer whose send Core will refuse.
actor ConversationWriteAccessResolver: ConversationWriteAccessResolving {

    private let channelRepository: ChannelRepositoryProtocol
    private let communityRepository: CommunityRepositoryProtocol
    private let currentUserId: @Sendable () -> String

    init(
        channelRepository: ChannelRepositoryProtocol,
        communityRepository: CommunityRepositoryProtocol,
        currentUserId: @escaping @Sendable () -> String
    ) {
        self.channelRepository = channelRepository
        self.communityRepository = communityRepository
        self.currentUserId = currentUserId
    }

    func restriction(forConversationId conversationId: String) async -> ConversationWriteRestriction? {
        guard !conversationId.isEmpty else { return nil }

        if let channel = try? await channelRepository.channel(forConversationId: conversationId) {
            return channel.canPost(as: currentUserId()) ? nil : .channelOwnerOnly
        }

        if let context = try? await communityRepository.groupContext(forConversationId: conversationId) {
            guard context.group.isAnnouncementGroup else { return nil }
            return context.group.canWrite(as: context.community.myRole) ? nil : .announcementsAdminsOnly
        }

        return nil
    }
}
