//
//  ChannelResponseDto.swift
//  FeatureChat
//
//  What /identity/channels returns.
//

import Foundation

public struct ChannelDto: Decodable {

    let id: String

    /// Identity names it `channelName`; `name` is accepted for the routes that
    /// answer with the shorter spelling.
    let channelName: String?
    let name: String?

    let channelType: String?
    let image: String?
    /// Not on the wire yet — served from the debug mock store until Identity
    /// carries it. See `ChannelCommunityDebugConfiguration`.
    let description: String?

    /// Core `BROADCAST` conversation. Absent on channels created before the V12
    /// migration — see `Channel.conversationId`.
    let conversationId: String?

    let createdByUserId: String?
    let subscriberCount: Int?
    let isSubscribed: Bool?

    /// Users who follow the channel and are not banned from it.
    ///
    /// `nil` when the route does not send the list — `/identity/channels/byId`
    /// omits it, the listing and the subscription response carry it. An empty
    /// array is an answer ("nobody follows"); `nil` is the absence of one, and
    /// the two must not be confused.
    let subscriberIds: [String]?

    let createdAt: String?
    let updatedAt: String?

    var resolvedName: String {
        channelName ?? name ?? ""
    }

    /// Decoded by hand because Identity has more than one name for the same
    /// facts, and a key we do not read decodes as nil — which is why a channel
    /// with followers still displayed zero. Every spelling seen on the wire or
    /// in the integration doc is accepted; the first one present wins.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        channelName = try container.decodeIfPresent(String.self, forKey: .channelName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        channelType = try container.decodeIfPresent(String.self, forKey: .channelType)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
        createdByUserId = try container.decodeIfPresent(String.self, forKey: .createdByUserId)
            ?? container.decodeIfPresent(String.self, forKey: .ownerId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)

        subscriberCount = try Self.firstInt(
            in: container,
            keys: [.subscriberCount, .subscribersCount, .followerCount, .followersCount, .totalSubscribers]
        )

        isSubscribed = try container.decodeIfPresent(Bool.self, forKey: .isSubscribed)
            ?? container.decodeIfPresent(Bool.self, forKey: .subscribed)
            ?? container.decodeIfPresent(Bool.self, forKey: .following)

        // `try?`: a subscriber list in an unexpected shape costs the list, not
        // the channel — the repository then falls back to the inbox.
        let subscribers: [ChannelSubscriberDto]? = try? container.decodeIfPresent(
            [ChannelSubscriberDto].self, forKey: .subscribers
        )
        subscriberIds = subscribers?
            .filter { $0.banned != true }
            .map(\.userId)
    }

    private static func firstInt(
        in container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) throws -> Int? {
        for key in keys {
            if let value = try container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, channelName, name, channelType, image, description
        case conversationId, createdByUserId, ownerId
        case subscriberCount, subscribersCount, followerCount, followersCount, totalSubscribers
        case isSubscribed, subscribed, following
        case subscribers
        case createdAt, updatedAt
    }

    /// Kept for the debug mock store, which rebuilds a DTO to add a description.
    init(
        id: String,
        channelName: String?,
        name: String?,
        channelType: String?,
        image: String?,
        description: String?,
        conversationId: String?,
        createdByUserId: String?,
        subscriberCount: Int?,
        isSubscribed: Bool?,
        createdAt: String?,
        updatedAt: String?,
        subscriberIds: [String]? = nil
    ) {
        self.id = id
        self.channelName = channelName
        self.name = name
        self.channelType = channelType
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
}

/// One entry of `subscribers[]`.
struct ChannelSubscriberDto: Decodable {
    let userId: String
    /// A banned subscriber is still listed, but no longer follows.
    let banned: Bool?
}

/// An admin of a channel — someone other than the creator who may post.
public struct ChannelAdminDto: Codable {
    let userId: String
    let userName: String?
    let avatar: String?
    let addedAt: String?
}

public typealias ChannelAPIResponse = IdentityAPIResponse<ChannelDto>
public typealias ChannelAdminListAPIResponse = IdentityAPIResponse<[ChannelAdminDto]>
public typealias ChannelListAPIResponse = IdentityAPIResponse<[ChannelDto]>
public typealias ChannelMutationAPIResponse = IdentityAPIResponse<EmptyIdentityPayload>

// MARK: - Channel Invite Link Responses

/// Response from `POST /identity/channels/{channelId}/invite-link`
/// and `GET /identity/channels/{channelId}/invite-link`
public struct ChannelInviteLinkDto: Codable {
    /// The unique invite code (e.g., "ABC123XYZ")
    let inviteCode: String
    
    /// Full shareable URL (e.g., "https://waangu.app/channel/invite/ABC123XYZ")
    let inviteUrl: String
    
    /// Channel ID this link is for
    let channelId: String
    
    /// When the link was created/regenerated
    let createdAt: String
    
    /// When the link expires (ISO 8601). Nil if never expires.
    let expiresAt: String?
    
    /// Maximum number of uses allowed. Nil if unlimited.
    let maxUses: Int?
    
    /// Current number of uses
    let currentUses: Int
    
    /// Whether the link is still active
    let isActive: Bool
}

/// Response from `POST /identity/channels/join-by-code`
public struct JoinChannelByCodeResponseDto: Decodable {
    /// The channel that was joined
    let channel: ChannelDto
    
    /// Whether the user was successfully subscribed
    let subscribed: Bool
    
    /// Whether this was a new subscription or already subscribed
    let wasAlreadySubscribed: Bool?
}

public typealias ChannelInviteLinkAPIResponse = IdentityAPIResponse<ChannelInviteLinkDto>
public typealias JoinChannelByCodeAPIResponse = IdentityAPIResponse<JoinChannelByCodeResponseDto>
