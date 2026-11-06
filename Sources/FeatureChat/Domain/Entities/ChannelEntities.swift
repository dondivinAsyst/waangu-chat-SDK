//
//  ChannelEntities.swift
//  FeatureChat
//
//  Canaux Updates — a channel is Identity metadata plus one Core BROADCAST
//  conversation. Not to be confused with `ConversationChannel.WHATSAPP`, which
//  is omnichannel support routing.
//

import Foundation

// MARK: - Channel Type

/// Kind of channel, as Identity spells it.
///
/// A struct rather than an enum so a value this app has not been taught yet
/// decodes instead of failing the whole response.
public struct ChannelType: RawRepresentable, Hashable, Sendable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let text = ChannelType(rawValue: "TEXT")
}

extension ChannelType: Codable {

    /// Encoded as the bare string Identity uses — `"TEXT"`, not
    /// `{"rawValue": "TEXT"}`, which is what synthesis would produce for a
    /// struct.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Channel

public struct Channel: Identifiable, Equatable, Sendable {

    public let id: String
    public var name: String
    public var type: ChannelType
    public var image: String?

    /// What the channel is about. Mocked locally until Identity carries it.
    public var description: String?

    /// The Core `BROADCAST` conversation this channel posts into.
    ///
    /// Nil for channels created before Identity's V12 migration. Such a channel
    /// can be listed but not opened and not posted to — the fix is server-side
    /// (recreate or backfill), so the UI shows it as unavailable rather than
    /// opening an empty room.
    public var conversationId: String?

    public var createdByUserId: String
    public var subscriberCount: Int

    /// Whether this user is subscribed.
    ///
    /// Resolved by the repository: Identity's subscriber list when the route
    /// sends one, the inbox otherwise. See `ChannelFollowing`.
    public var isSubscribed: Bool

    /// Users who follow the channel, not banned — as Identity listed them.
    ///
    /// `nil` when the route did not send the list (`/identity/channels/byId`).
    /// Empty means nobody follows; the two are different answers.
    public var subscriberIds: [String]?

    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String,
        name: String,
        type: ChannelType = .text,
        image: String? = nil,
        description: String? = nil,
        conversationId: String? = nil,
        createdByUserId: String = "",
        subscriberCount: Int = 0,
        isSubscribed: Bool = false,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        subscriberIds: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.image = image
        self.description = description
        self.conversationId = conversationId
        self.createdByUserId = createdByUserId
        self.subscriberCount = subscriberCount
        self.isSubscribed = isSubscribed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.subscriberIds = subscriberIds
    }

    /// A channel with no conversation cannot be opened — see `conversationId`.
    public var isOpenable: Bool {
        !(conversationId ?? "").isEmpty
    }

    public func isOwned(by userId: String) -> Bool {
        !userId.isEmpty && createdByUserId.caseInsensitiveCompare(userId) == .orderedSame
    }

    /// Only the creator posts. Core is expected to enforce this too (phase 2 of
    /// the backend), so this gate is about not offering a composer that would be
    /// rejected — never the only check.
    public func canPost(as userId: String) -> Bool {
        isOpenable && isOwned(by: userId)
    }
}

// MARK: - Admin

/// Someone besides the creator who may post to a channel.
public struct ChannelAdmin: Identifiable, Equatable, Sendable {

    public let userId: String
    public var userName: String
    public var avatar: String?
    public var addedAt: Date?

    public init(userId: String, userName: String, avatar: String? = nil, addedAt: Date? = nil) {
        self.userId = userId
        self.userName = userName
        self.avatar = avatar
        self.addedAt = addedAt
    }

    public var id: String { userId }
}

// MARK: - Draft

public struct NewChannelDraft: Equatable, Sendable {

    public var name: String
    public var type: ChannelType
    public var image: String?
    public var description: String?

    public init(
        name: String,
        type: ChannelType = .text,
        image: String? = nil,
        description: String? = nil
    ) {
        self.name = name
        self.type = type
        self.image = image
        self.description = description
    }
}

// MARK: - Subscription Outcome

public enum ChannelSubscriptionOutcome: Equatable, Sendable {
    case subscribed(channelId: String, conversationId: String?)
    case unsubscribed(channelId: String)
}

// MARK: - Errors

public enum ChannelError: Error, Equatable, Sendable {

    /// Subscriber banned from this channel.
    case banned
    /// The channel belongs to another tenant than the current session.
    case tenantMismatch
    case notFound
    case forbidden

    /// Channel created before Identity's V12 migration: no `conversationId`, so
    /// there is nothing to open or post to.
    case missingConversation

    case server(code: String?, message: String?)
}

extension ChannelError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .banned:
            return "You have been banned from this channel."
        case .tenantMismatch:
            return "This channel is not available for your account."
        case .notFound:
            return "This channel no longer exists."
        case .forbidden:
            return "You are not allowed to do this."
        case .missingConversation:
            return "This channel is not ready yet."
        case .server(let code, let message):
            return message ?? code ?? "The channel service is unavailable."
        }
    }
}


// MARK: - Channel Invite Link

/// A shareable invite link for a channel.
///
/// Channel owners can generate these links to share outside the app (via WhatsApp,
/// SMS, email, etc.). Recipients open the link, which deep links into the app and
/// shows a preview sheet where they can subscribe to the channel.
public struct ChannelInviteLink: Identifiable, Equatable, Sendable {
    
    public let id: String // Uses inviteCode as ID
    
    /// The unique invite code (e.g., "ABC123XYZ")
    public let inviteCode: String
    
    /// Full shareable URL (e.g., "https://waangu.app/channel/invite/ABC123XYZ")
    public let inviteUrl: String
    
    /// Channel ID this link is for
    public let channelId: String
    
    /// When the link was created/regenerated
    public let createdAt: Date
    
    /// When the link expires. Nil if never expires.
    public let expiresAt: Date?
    
    /// Maximum number of uses allowed. Nil if unlimited.
    public let maxUses: Int?
    
    /// Current number of uses
    public let currentUses: Int
    
    /// Whether the link is still active (not expired, not over max uses, not revoked)
    public var isActive: Bool
    
    /// Whether the link has expired
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
    /// Whether the link has reached its maximum uses
    public var hasReachedMaxUses: Bool {
        guard let maxUses = maxUses else { return false }
        return currentUses >= maxUses
    }
    
    public init(
        inviteCode: String,
        inviteUrl: String,
        channelId: String,
        createdAt: Date,
        expiresAt: Date? = nil,
        maxUses: Int? = nil,
        currentUses: Int = 0,
        isActive: Bool = true
    ) {
        self.id = inviteCode
        self.inviteCode = inviteCode
        self.inviteUrl = inviteUrl
        self.channelId = channelId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.maxUses = maxUses
        self.currentUses = currentUses
        self.isActive = isActive
    }
}
