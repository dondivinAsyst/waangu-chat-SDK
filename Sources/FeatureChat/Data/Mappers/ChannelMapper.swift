//
//  ChannelMapper.swift
//  FeatureChat
//
//  Channel DTOs ↔ entities, and Identity's error names → ChannelError.
//

import Foundation
import WaanguNetworkKit

enum ChannelMapper {

    // MARK: - DTO → Entity

    /// `isSubscribed` is only a starting value here. The repository decides it
    /// with `ChannelFollowing`: the subscriber list when Identity sends one,
    /// the inbox when it does not.
    static func toDomain(_ dto: ChannelDto) -> Channel {
        Channel(
            id: dto.id,
            name: dto.resolvedName,
            type: ChannelType(rawValue: dto.channelType ?? ChannelType.text.rawValue),
            image: dto.image,
            description: dto.description,
            conversationId: dto.conversationId,
            createdByUserId: dto.createdByUserId ?? "",
            subscriberCount: dto.subscriberCount ?? 0,
            isSubscribed: dto.isSubscribed ?? false,
            createdAt: ISO8601Timestamp.date(from: dto.createdAt),
            updatedAt: ISO8601Timestamp.date(from: dto.updatedAt),
            subscriberIds: dto.subscriberIds
        )
    }

    // MARK: - Entity → Request

    static func toRequest(_ draft: NewChannelDraft) -> CreateChannelRequest {
        CreateChannelRequest(
            channelName: draft.name,
            channelType: draft.type.rawValue,
            image: draft.image,
            description: draft.description
        )
    }

    static func toDomain(_ dto: ChannelAdminDto) -> ChannelAdmin {
        ChannelAdmin(
            userId: dto.userId,
            userName: dto.userName ?? "",
            avatar: dto.avatar,
            addedAt: ISO8601Timestamp.date(from: dto.addedAt)
        )
    }
}

// MARK: - Errors

enum ChannelErrorMapper {

    /// `subscribing` distinguishes the one 403 the doc documents: a banned
    /// subscriber. Everywhere else a 403 is just a refusal — the API client
    /// drops the body on 403, so there is nothing else to read.
    static func map(_ error: Error, subscribing: Bool = false) -> ChannelError {
        if let channel = error as? ChannelError { return channel }

        guard let apiError = error as? APIError else {
            return .server(code: nil, message: error.localizedDescription)
        }

        switch apiError {
        case .notFound:
            return .notFound
        case .forbidden:
            return subscribing ? .banned : .forbidden
        case .unauthorized:
            return .forbidden
        case .badRequest(let message):
            return named(message) ?? .server(code: nil, message: message)
        case .clientError(_, let message):
            return named(message) ?? .server(code: nil, message: message)
        default:
            return .server(code: nil, message: apiError.errorDescription)
        }
    }

    private static func named(_ message: String?) -> ChannelError? {
        guard let message, !message.isEmpty else { return nil }
        let upper = message.uppercased()

        if upper.contains("CHANNEL_BANNED") { return .banned }
        if upper.contains("CHANNEL_TENANT_MISMATCH") { return .tenantMismatch }
        if upper.contains("NOT_FOUND") { return .notFound }

        return nil
    }
}


// MARK: - Channel Invite Link Mapping

extension ChannelMapper {
    
    /// Maps invite link DTO to domain entity
    static func toDomain(_ dto: ChannelInviteLinkDto) -> ChannelInviteLink {
        ChannelInviteLink(
            inviteCode: dto.inviteCode,
            inviteUrl: dto.inviteUrl,
            channelId: dto.channelId,
            createdAt: ISO8601Timestamp.date(from: dto.createdAt) ?? Date(),
            expiresAt: ISO8601Timestamp.date(from: dto.expiresAt),
            maxUses: dto.maxUses,
            currentUses: dto.currentUses,
            isActive: dto.isActive
        )
    }
    
    /// Maps join-by-code response DTO to domain
    static func toDomain(_ dto: JoinChannelByCodeResponseDto) -> (channel: Channel, wasAlreadySubscribed: Bool) {
        let channel = toDomain(dto.channel)
        return (channel, dto.wasAlreadySubscribed ?? false)
    }
}
