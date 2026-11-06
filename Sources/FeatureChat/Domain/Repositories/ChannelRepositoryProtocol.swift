//
//  ChannelRepositoryProtocol.swift
//  FeatureChat
//

import Foundation

/// Canaux Updates as the domain sees them.
///
/// Failures are reported as `ChannelError` — never as a transport error.
protocol ChannelRepositoryProtocol {

    /// Everything Identity lists, with `isSubscribed` resolved against the inbox.
    func channels(page: Int, size: Int) async throws -> [Channel]

    /// The channels this user actually follows.
    ///
    /// A subscription is a `BROADCAST` conversation in the inbox, so this reads
    /// the local conversations and names them from the Identity listing.
    func subscribedChannels() async throws -> [Channel]

    func channel(id: String) async throws -> Channel

    /// The channel a broadcast conversation belongs to, if it is one.
    ///
    /// Identity has no lookup by conversation, so this is matched against the
    /// listing this device already holds.
    func channel(forConversationId conversationId: String) async throws -> Channel?

    func create(_ draft: NewChannelDraft) async throws -> Channel

    func update(
        channelId: String,
        name: String?,
        type: ChannelType?,
        image: String?,
        description: String?
    ) async throws -> Channel

    /// Admins besides the creator. Mocked until Identity exposes the route.
    func admins(channelId: String) async throws -> [ChannelAdmin]
    func addAdmin(channelId: String, userId: String, userName: String) async throws
    func removeAdmin(channelId: String, userId: String) async throws

    func subscribe(channelId: String) async throws -> ChannelSubscriptionOutcome
    func unsubscribe(channelId: String) async throws -> ChannelSubscriptionOutcome
    
    // Invite link operations
    func generateInviteLink(
        channelId: String,
        expiresIn: Int?,
        maxUses: Int?
    ) async throws -> ChannelInviteLink
    
    func getInviteLink(channelId: String) async throws -> ChannelInviteLink
    func revokeInviteLink(channelId: String) async throws
    func joinByCode(inviteCode: String) async throws -> (channel: Channel, wasAlreadySubscribed: Bool)
}
