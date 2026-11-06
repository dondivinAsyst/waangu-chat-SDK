//
//  ChannelRequests.swift
//  FeatureChat
//
//  Bodies for POST/PUT on /identity/channels.
//

import Foundation

/// `POST /channels`
///
/// Identity also creates the Core `BROADCAST` conversation and persists its id
/// on the channel.
public struct CreateChannelRequest: Codable, Sendable {
    let channelName: String
    let channelType: String
    let image: String?
    /// Mocked until Identity carries it — see `ChannelCommunityDebugConfiguration`.
    let description: String?
}

/// `PUT /channels`
public struct UpdateChannelRequest: Codable, Sendable {
    let channelId: String
    let channelName: String?
    let channelType: String?
    let image: String?
    let description: String?
}

/// `POST /channels/admins` and `DELETE /channels/admins` — mocked for now.
public struct ChannelAdminRequest: Codable, Sendable {
    let channelId: String
    let userId: String
    let userName: String?
}

/// `POST /channels/subscription` — the unified endpoint.
///
/// `/channels/subscribe` and `/channels/unsubscribe` do the same job with the
/// verb in the path; this client uses the unified one so subscribe and
/// unsubscribe cannot drift apart.
public struct ChannelSubscriptionRequest: Codable, Sendable {

    let channelId: String
    let subscribe: Bool

    // Named `subscribing`/`unsubscribing` because `subscribe` is already an
    // instance property on this type.

    static func subscribing(to channelId: String) -> ChannelSubscriptionRequest {
        .init(channelId: channelId, subscribe: true)
    }

    static func unsubscribing(from channelId: String) -> ChannelSubscriptionRequest {
        .init(channelId: channelId, subscribe: false)
    }
}

// MARK: - Channel Invite Link Requests

/// `POST /identity/channels/{channelId}/invite-link`
///
/// Generates a shareable invite link for the channel. If a link already exists,
/// this endpoint regenerates it with a new code (revokes the old one).
public struct GenerateChannelInviteLinkRequest: Codable, Sendable {
    let channelId: String
    
    /// Optional expiration time in seconds from now. If nil, link never expires.
    let expiresIn: Int?
    
    /// Optional maximum number of uses. If nil, unlimited uses.
    let maxUses: Int?
    
    init(channelId: String, expiresIn: Int? = nil, maxUses: Int? = nil) {
        self.channelId = channelId
        self.expiresIn = expiresIn
        self.maxUses = maxUses
    }
}

/// `POST /identity/channels/join-by-code`
///
/// Allows a user to subscribe to a channel using an invite code from a link.
public struct JoinChannelByCodeRequest: Codable, Sendable {
    let inviteCode: String
    
    init(inviteCode: String) {
        self.inviteCode = inviteCode
    }
}

/// `DELETE /identity/channels/{channelId}/invite-link`
///
/// Revokes the current invite link for the channel, making it invalid.
public struct RevokeChannelInviteLinkRequest: Codable, Sendable {
    let channelId: String
    
    init(channelId: String) {
        self.channelId = channelId
    }
}
