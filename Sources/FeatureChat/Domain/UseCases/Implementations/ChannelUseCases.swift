//
//  ChannelUseCases.swift
//  FeatureChat
//

import Foundation

// MARK: - Container

public final class ChannelUseCases: ChannelUseCasesProtocol {

    public let listChannels: ListChannelsUseCaseProtocol
    public let listSubscribed: ListSubscribedChannelsUseCaseProtocol
    public let getChannel: GetChannelUseCaseProtocol
    public let createChannel: CreateChannelUseCaseProtocol
    public let updateChannel: UpdateChannelUseCaseProtocol
    public let subscription: ChannelSubscriptionUseCaseProtocol
    public let manageAdmins: ManageChannelAdminsUseCaseProtocol
    public let openConversation: OpenChannelConversationUseCaseProtocol
    
    // Invite link operations
    public let generateInviteLink: GenerateChannelInviteLinkUseCaseProtocol
    public let getInviteLink: GetChannelInviteLinkUseCaseProtocol
    public let revokeInviteLink: RevokeChannelInviteLinkUseCaseProtocol
    public let joinByCode: JoinChannelByCodeUseCaseProtocol

    init(repository: ChannelRepositoryProtocol) {
        self.listChannels = ListChannelsUseCase(repository: repository)
        self.listSubscribed = ListSubscribedChannelsUseCase(repository: repository)
        self.getChannel = GetChannelUseCase(repository: repository)
        self.createChannel = CreateChannelUseCase(repository: repository)
        self.updateChannel = UpdateChannelUseCase(repository: repository)
        self.subscription = ChannelSubscriptionUseCase(repository: repository)
        self.manageAdmins = ManageChannelAdminsUseCase(repository: repository)
        self.openConversation = OpenChannelConversationUseCase(repository: repository)
        
        // Invite link use cases
        self.generateInviteLink = GenerateChannelInviteLinkUseCase(repository: repository)
        self.getInviteLink = GetChannelInviteLinkUseCase(repository: repository)
        self.revokeInviteLink = RevokeChannelInviteLinkUseCase(repository: repository)
        self.joinByCode = JoinChannelByCodeUseCase(repository: repository)
    }
}

// MARK: - Reading

struct ListChannelsUseCase: ListChannelsUseCaseProtocol {

    let repository: ChannelRepositoryProtocol

    func execute(page: Int, size: Int) async throws -> [Channel] {
        try await repository.channels(page: page, size: size)
    }
}

struct ListSubscribedChannelsUseCase: ListSubscribedChannelsUseCaseProtocol {

    let repository: ChannelRepositoryProtocol

    func execute() async throws -> [Channel] {
        try await repository.subscribedChannels()
    }
}

struct GetChannelUseCase: GetChannelUseCaseProtocol {

    let repository: ChannelRepositoryProtocol

    func execute(channelId: String) async throws -> Channel {
        guard !channelId.isEmpty else { throw ChannelError.notFound }
        return try await repository.channel(id: channelId)
    }
}

// MARK: - Writing

struct CreateChannelUseCase: CreateChannelUseCaseProtocol {

    let repository: ChannelRepositoryProtocol

    func execute(_ draft: NewChannelDraft) async throws -> Channel {
        var draft = draft
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.name.isEmpty else {
            throw ChannelError.server(code: nil, message: "A channel needs a name.")
        }

        let channel = try await repository.create(draft)

        // A channel Identity created without a conversation cannot be posted to.
        // Saying so here beats a channel that silently swallows every message.
        guard channel.isOpenable else { throw ChannelError.missingConversation }
        return channel
    }
}

struct UpdateChannelUseCase: UpdateChannelUseCaseProtocol {

    let repository: ChannelRepositoryProtocol

    func execute(
        channelId: String,
        name: String?,
        type: ChannelType?,
        image: String?,
        description: String?
    ) async throws -> Channel {
        try await repository.update(
            channelId: channelId,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            image: image,
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct ManageChannelAdminsUseCase: ManageChannelAdminsUseCaseProtocol {

    let repository: ChannelRepositoryProtocol

    func list(channelId: String) async throws -> [ChannelAdmin] {
        try await repository.admins(channelId: channelId)
    }

    func add(channelId: String, userId: String, userName: String) async throws {
        guard !userId.isEmpty else { throw ChannelError.notFound }
        try await repository.addAdmin(channelId: channelId, userId: userId, userName: userName)
    }

    func remove(channelId: String, userId: String) async throws {
        try await repository.removeAdmin(channelId: channelId, userId: userId)
    }
}

// MARK: - Subscription

struct ChannelSubscriptionUseCase: ChannelSubscriptionUseCaseProtocol {

    let repository: ChannelRepositoryProtocol

    func subscribe(channelId: String) async throws -> ChannelSubscriptionOutcome {
        guard !channelId.isEmpty else { throw ChannelError.notFound }
        return try await repository.subscribe(channelId: channelId)
    }

    func unsubscribe(channelId: String) async throws -> ChannelSubscriptionOutcome {
        guard !channelId.isEmpty else { throw ChannelError.notFound }
        return try await repository.unsubscribe(channelId: channelId)
    }
}

// MARK: - Opening a conversation

struct OpenChannelConversationUseCase: OpenChannelConversationUseCaseProtocol {

    let repository: ChannelRepositoryProtocol

    func execute(channelId: String) async throws -> String {
        let channel = try await repository.channel(id: channelId)
        guard let conversationId = channel.conversationId, !conversationId.isEmpty else {
            throw ChannelError.missingConversation
        }
        return conversationId
    }
}

// MARK: - Invite Link Operations

struct GenerateChannelInviteLinkUseCase: GenerateChannelInviteLinkUseCaseProtocol {
    
    let repository: ChannelRepositoryProtocol
    
    func execute(
        channelId: String,
        expiresIn: Int?,
        maxUses: Int?
    ) async throws -> ChannelInviteLink {
        guard !channelId.isEmpty else { throw ChannelError.notFound }
        return try await repository.generateInviteLink(
            channelId: channelId,
            expiresIn: expiresIn,
            maxUses: maxUses
        )
    }
}

struct GetChannelInviteLinkUseCase: GetChannelInviteLinkUseCaseProtocol {
    
    let repository: ChannelRepositoryProtocol
    
    func execute(channelId: String) async throws -> ChannelInviteLink {
        guard !channelId.isEmpty else { throw ChannelError.notFound }
        return try await repository.getInviteLink(channelId: channelId)
    }
}

struct RevokeChannelInviteLinkUseCase: RevokeChannelInviteLinkUseCaseProtocol {
    
    let repository: ChannelRepositoryProtocol
    
    func execute(channelId: String) async throws {
        guard !channelId.isEmpty else { throw ChannelError.notFound }
        try await repository.revokeInviteLink(channelId: channelId)
    }
}

struct JoinChannelByCodeUseCase: JoinChannelByCodeUseCaseProtocol {
    
    let repository: ChannelRepositoryProtocol
    
    func execute(inviteCode: String) async throws -> (channel: Channel, wasAlreadySubscribed: Bool) {
        guard !inviteCode.isEmpty else {
            throw ChannelError.server(code: nil, message: "Invite code cannot be empty")
        }
        return try await repository.joinByCode(inviteCode: inviteCode)
    }
}
