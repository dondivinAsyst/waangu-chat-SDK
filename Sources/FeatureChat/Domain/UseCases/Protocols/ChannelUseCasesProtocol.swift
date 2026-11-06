//
//  ChannelUseCasesProtocol.swift
//  FeatureChat
//

import Foundation

public protocol ListChannelsUseCaseProtocol {
    /// Discovery listing — everything Identity knows.
    func execute(page: Int, size: Int) async throws -> [Channel]
}

public protocol ListSubscribedChannelsUseCaseProtocol {
    /// What this user follows, resolved against the inbox.
    func execute() async throws -> [Channel]
}

public protocol GetChannelUseCaseProtocol {
    func execute(channelId: String) async throws -> Channel
}

public protocol CreateChannelUseCaseProtocol {
    func execute(_ draft: NewChannelDraft) async throws -> Channel
}

public protocol UpdateChannelUseCaseProtocol {
    func execute(
        channelId: String,
        name: String?,
        type: ChannelType?,
        image: String?,
        description: String?
    ) async throws -> Channel
}

/// Channel admins — who else may post. Served from a mock until Identity has the
/// route; the contract is the one the real endpoint will honour.
public protocol ManageChannelAdminsUseCaseProtocol {
    func list(channelId: String) async throws -> [ChannelAdmin]
    func add(channelId: String, userId: String, userName: String) async throws
    func remove(channelId: String, userId: String) async throws
}

public protocol ChannelSubscriptionUseCaseProtocol {
    func subscribe(channelId: String) async throws -> ChannelSubscriptionOutcome
    func unsubscribe(channelId: String) async throws -> ChannelSubscriptionOutcome
}

/// The `BROADCAST` conversation to open for a channel.
///
/// Throws `ChannelError.missingConversation` for a channel created before
/// Identity's V12 migration — it has no conversation, so there is nothing to
/// open and no message to send.
public protocol OpenChannelConversationUseCaseProtocol {
    func execute(channelId: String) async throws -> String
}

// MARK: - Invite Link Use Cases

/// Generate or regenerate a shareable invite link for a channel.
/// Only channel owners can generate links.
public protocol GenerateChannelInviteLinkUseCaseProtocol {
    func execute(
        channelId: String,
        expiresIn: Int?,
        maxUses: Int?
    ) async throws -> ChannelInviteLink
}

/// Get the current invite link for a channel.
public protocol GetChannelInviteLinkUseCaseProtocol {
    func execute(channelId: String) async throws -> ChannelInviteLink
}

/// Revoke the current invite link for a channel, making it invalid.
/// Only channel owners can revoke links.
public protocol RevokeChannelInviteLinkUseCaseProtocol {
    func execute(channelId: String) async throws
}

/// Join a channel using an invite code from a shareable link.
/// Returns the channel and whether the user was already subscribed.
public protocol JoinChannelByCodeUseCaseProtocol {
    func execute(inviteCode: String) async throws -> (channel: Channel, wasAlreadySubscribed: Bool)
}

// MARK: - Container

public protocol ChannelUseCasesProtocol {
    var listChannels: ListChannelsUseCaseProtocol { get }
    var listSubscribed: ListSubscribedChannelsUseCaseProtocol { get }
    var getChannel: GetChannelUseCaseProtocol { get }
    var createChannel: CreateChannelUseCaseProtocol { get }
    var updateChannel: UpdateChannelUseCaseProtocol { get }
    var subscription: ChannelSubscriptionUseCaseProtocol { get }
    var manageAdmins: ManageChannelAdminsUseCaseProtocol { get }
    var openConversation: OpenChannelConversationUseCaseProtocol { get }
    
    // Invite link operations
    var generateInviteLink: GenerateChannelInviteLinkUseCaseProtocol { get }
    var getInviteLink: GetChannelInviteLinkUseCaseProtocol { get }
    var revokeInviteLink: RevokeChannelInviteLinkUseCaseProtocol { get }
    var joinByCode: JoinChannelByCodeUseCaseProtocol { get }
}
