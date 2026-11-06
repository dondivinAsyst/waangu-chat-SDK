//
//  ChannelRepository.swift
//  FeatureChat
//
//  Identity for the metadata, the inbox for what this user follows.
//

import Foundation
import WaanguCoreKit

/// Identity supplies the names, images and — on the listing and the
/// subscription response — the subscriber list. Who follows what is decided by
/// `ChannelFollowing`: that list when it is sent, the inbox when it is not.
actor ChannelRepository: ChannelRepositoryProtocol {

    private let remoteDataSource: RemoteChannelDataSourceProtocol
    private let database: any DatabaseRepositoryProtocol
    private let logger: any AppLoggerProtocol

    private var cachedChannels: [Channel]?

    init(
        remoteDataSource: RemoteChannelDataSourceProtocol,
        database: any DatabaseRepositoryProtocol,
        logger: any AppLoggerProtocol
    ) {
        self.remoteDataSource = remoteDataSource
        self.database = database
        self.logger = logger
    }

    // MARK: - Read

    func channels(page: Int, size: Int) async throws -> [Channel] {
        do {
            let dtos = try await remoteDataSource.listChannels(page: page, size: size)
            let subscribed = await subscribedConversationIds()
            let channels = dtos.map { dto -> Channel in
                var channel = ChannelMapper.toDomain(dto)
                channel.isSubscribed = isFollowed(channel, inboxConversationIds: subscribed)
                return channel
            }
            if page == 0 { cachedChannels = channels }
            return channels
        } catch {
            throw await mapped(error, context: "channels")
        }
    }

    func subscribedChannels() async throws -> [Channel] {
        let subscribed = await subscribedConversationIds()
        let known = try await allChannels()

        return known
            .filter { isFollowed($0, inboxConversationIds: subscribed) }
            .map { channel in
                var channel = channel
                channel.isSubscribed = true
                return channel
            }
    }

    func channel(id: String) async throws -> Channel {
        do {
            let dto = try await remoteDataSource.getChannel(id: id)
            var channel = ChannelMapper.toDomain(dto)
            let subscribed = await subscribedConversationIds()
            channel.isSubscribed = isFollowed(channel, inboxConversationIds: subscribed)
            return channel
        } catch {
            throw await mapped(error, context: "channel(id:)")
        }
    }

    func channel(forConversationId conversationId: String) async throws -> Channel? {
        guard !conversationId.isEmpty else { return nil }
        return try await allChannels().first { $0.conversationId == conversationId }
    }

    // MARK: - Write

    func create(_ draft: NewChannelDraft) async throws -> Channel {
        do {
            let dto = try await remoteDataSource.createChannel(ChannelMapper.toRequest(draft))
            var channel = ChannelMapper.toDomain(dto)
            // The creator is a participant of the BROADCAST conversation from
            // the moment Identity creates it.
            channel.isSubscribed = true
            cachedChannels = nil
            return channel
        } catch {
            throw await mapped(error, context: "create")
        }
    }

    func update(
        channelId: String,
        name: String?,
        type: ChannelType?,
        image: String?,
        description: String?
    ) async throws -> Channel {
        do {
            let dto = try await remoteDataSource.updateChannel(
                UpdateChannelRequest(
                    channelId: channelId,
                    channelName: name,
                    channelType: type?.rawValue,
                    image: image,
                    description: description
                )
            )
            cachedChannels = nil
            return ChannelMapper.toDomain(dto)
        } catch {
            throw await mapped(error, context: "update")
        }
    }

    // MARK: - Admins

    func admins(channelId: String) async throws -> [ChannelAdmin] {
        do {
            return try await remoteDataSource.listAdmins(channelId: channelId)
                .map { ChannelMapper.toDomain($0) }
        } catch {
            throw await mapped(error, context: "admins")
        }
    }

    func addAdmin(channelId: String, userId: String, userName: String) async throws {
        do {
            try await remoteDataSource.addAdmin(
                ChannelAdminRequest(channelId: channelId, userId: userId, userName: userName)
            )
        } catch {
            throw await mapped(error, context: "addAdmin")
        }
    }

    func removeAdmin(channelId: String, userId: String) async throws {
        do {
            try await remoteDataSource.removeAdmin(
                ChannelAdminRequest(channelId: channelId, userId: userId, userName: nil)
            )
        } catch {
            throw await mapped(error, context: "removeAdmin")
        }
    }

    func subscribe(channelId: String) async throws -> ChannelSubscriptionOutcome {
        do {
            try await remoteDataSource.changeSubscription(.subscribing(to: channelId))
            cachedChannels = nil
            // The conversation arrives with the next inbox sync, so the id is
            // read back from Identity rather than assumed.
            let refreshed = try? await remoteDataSource.getChannel(id: channelId)
            return .subscribed(channelId: channelId, conversationId: refreshed?.conversationId)
        } catch {
            throw await mapped(error, context: "subscribe", subscribing: true)
        }
    }

    func unsubscribe(channelId: String) async throws -> ChannelSubscriptionOutcome {
        do {
            try await remoteDataSource.changeSubscription(.unsubscribing(from: channelId))
            cachedChannels = nil
            return .unsubscribed(channelId: channelId)
        } catch {
            throw await mapped(error, context: "unsubscribe")
        }
    }
    
    // MARK: - Invite Links
    
    func generateInviteLink(
        channelId: String,
        expiresIn: Int?,
        maxUses: Int?
    ) async throws -> ChannelInviteLink {
        do {
            let request = GenerateChannelInviteLinkRequest(
                channelId: channelId,
                expiresIn: expiresIn,
                maxUses: maxUses
            )
            let dto = try await remoteDataSource.generateInviteLink(request)
            return ChannelMapper.toDomain(dto)
        } catch {
            throw await mapped(error, context: "generateInviteLink")
        }
    }
    
    func getInviteLink(channelId: String) async throws -> ChannelInviteLink {
        do {
            let dto = try await remoteDataSource.getInviteLink(channelId: channelId)
            return ChannelMapper.toDomain(dto)
        } catch {
            throw await mapped(error, context: "getInviteLink")
        }
    }
    
    func revokeInviteLink(channelId: String) async throws {
        do {
            let request = RevokeChannelInviteLinkRequest(channelId: channelId)
            try await remoteDataSource.revokeInviteLink(request)
        } catch {
            throw await mapped(error, context: "revokeInviteLink")
        }
    }
    
    func joinByCode(inviteCode: String) async throws -> (channel: Channel, wasAlreadySubscribed: Bool) {
        do {
            let request = JoinChannelByCodeRequest(inviteCode: inviteCode)
            let dto = try await remoteDataSource.joinByCode(request)
            let (channel, wasAlreadySubscribed) = ChannelMapper.toDomain(dto)
            
            // Clear cache since a new subscription may have been added
            if !wasAlreadySubscribed {
                cachedChannels = nil
            }
            
            return (channel, wasAlreadySubscribed)
        } catch {
            throw await mapped(error, context: "joinByCode")
        }
    }

    // MARK: - Private

    private static let pageSize = 50

    private func allChannels() async throws -> [Channel] {
        if let cachedChannels {
            return cachedChannels
        }
        do {
            let dtos = try await remoteDataSource.listChannels(page: 0, size: Self.pageSize)
            let channels = dtos.map { ChannelMapper.toDomain($0) }
            cachedChannels = channels
            return channels
        } catch {
            throw await mapped(error, context: "allChannels")
        }
    }

    private func isFollowed(_ channel: Channel, inboxConversationIds: Set<String>) -> Bool {
        ChannelFollowing.isFollowed(channel,
                                    currentUserId: CurrentSessionInfo.shared.currentUid,
                                    inboxConversationIds: inboxConversationIds)
    }

    /// Ids of the `BROADCAST` conversations this device holds.
    private func subscribedConversationIds() async -> Set<String> {
        let query = QuerySpec(
            filter: FilterSpec("type == %@", .string(ConversationTypeModel.channel.rawValue))
        )
        guard let conversations = try? await database.fetch(ConversationModel.self, query: query) else {
            return []
        }

        var ids = Set<String>()
        for conversation in conversations {
            ids.insert(conversation.id)
            if let serverId = conversation.serverId, !serverId.isEmpty {
                ids.insert(serverId)
            }
        }
        return ids
    }

    private func mapped(
        _ error: Error,
        context: String,
        subscribing: Bool = false
    ) async -> ChannelError {
        let mappedError = ChannelErrorMapper.map(error, subscribing: subscribing)
        await logger.log("Channel \(context) failed: \(mappedError)", level: .error)
        return mappedError
    }
}

// MARK: - Following

private extension Channel {

    /// A channel is followed when its conversation is one this device holds.
    func isFollowed(in conversationIds: Set<String>) -> Bool {
        guard let conversationId, !conversationId.isEmpty else { return false }
        return conversationIds.contains(conversationId)
    }
}

// MARK: - Who follows

/// Whether the current user follows a channel.
///
/// **The defect this replaced.** Following was read only from the inbox: a
/// channel counted as followed once its `BROADCAST` conversation was stored on
/// the device. That conversation arrives with a later inbox sync, so right
/// after a successful Follow the reload still said "not followed" and the
/// button never changed. The mirror bug: after Unfollow the conversation was
/// still stored, so the channel kept showing as followed.
///
/// The order, most authoritative first:
/// 1. **Created it.** Identity makes the creator the owner at creation.
/// 2. **Identity's subscriber list**, when the route sends one — it is the
///    server's answer, fresh from the same response that confirmed the change.
/// 3. **The inbox**, only when no list was sent (`/identity/channels/byId`).
enum ChannelFollowing {

    static func isFollowed(_ channel: Channel,
                           currentUserId: String,
                           inboxConversationIds: Set<String>) -> Bool {
        if channel.isOwned(by: currentUserId) { return true }
        if let subscriberIds = channel.subscriberIds {
            guard !currentUserId.isEmpty else { return false }
            return subscriberIds.contains { $0.caseInsensitiveCompare(currentUserId) == .orderedSame }
        }
        return channel.isFollowed(in: inboxConversationIds)
    }
}
