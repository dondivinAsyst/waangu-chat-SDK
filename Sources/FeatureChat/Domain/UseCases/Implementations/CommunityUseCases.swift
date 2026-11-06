//
//  CommunityUseCases.swift
//  FeatureChat
//

import Foundation

// MARK: - Container

public final class CommunityUseCases: CommunityUseCasesProtocol {

    public let listMine: ListMyCommunitiesUseCaseProtocol
    public let discover: DiscoverCommunitiesUseCaseProtocol
    public let getCommunity: GetCommunityUseCaseProtocol
    public let createCommunity: CreateCommunityUseCaseProtocol
    public let updateCommunity: UpdateCommunityUseCaseProtocol
    public let deleteCommunity: DeleteCommunityUseCaseProtocol
    public let joinCommunity: JoinCommunityUseCaseProtocol
    public let leaveCommunity: LeaveCommunityUseCaseProtocol
    public let manageMembers: ManageCommunityMembersUseCaseProtocol
    public let manageGroups: ManageCommunityGroupsUseCaseProtocol
    public let settings: CommunitySettingsUseCaseProtocol
    public let openConversation: OpenCommunityConversationUseCaseProtocol

    init(repository: CommunityRepositoryProtocol) {
        self.listMine = ListMyCommunitiesUseCase(repository: repository)
        self.discover = DiscoverCommunitiesUseCase(repository: repository)
        self.getCommunity = GetCommunityUseCase(repository: repository)
        self.createCommunity = CreateCommunityUseCase(repository: repository)
        self.updateCommunity = UpdateCommunityUseCase(repository: repository)
        self.deleteCommunity = DeleteCommunityUseCase(repository: repository)
        self.joinCommunity = JoinCommunityUseCase(repository: repository)
        self.leaveCommunity = LeaveCommunityUseCase(repository: repository)
        self.manageMembers = ManageCommunityMembersUseCase(repository: repository)
        self.manageGroups = ManageCommunityGroupsUseCase(repository: repository)
        self.settings = CommunitySettingsUseCase(repository: repository)
        self.openConversation = OpenCommunityConversationUseCase(repository: repository)
    }
}

// MARK: - Reading

struct ListMyCommunitiesUseCase: ListMyCommunitiesUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func execute(refresh: Bool) async throws -> [Community] {
        try await repository.myCommunities(refresh: refresh)
    }
}

struct DiscoverCommunitiesUseCase: DiscoverCommunitiesUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func execute(page: Int, size: Int) async throws -> [Community] {
        try await repository.discoverCommunities(page: page, size: size)
    }
}

struct GetCommunityUseCase: GetCommunityUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func execute(communityId: String) async throws -> Community {
        guard !communityId.isEmpty else { throw CommunityError.notFound }
        return try await repository.community(id: communityId)
    }
}

// MARK: - Writing

struct CreateCommunityUseCase: CreateCommunityUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func execute(_ draft: NewCommunityDraft) async throws -> Community {
        var draft = draft
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.name.isEmpty else {
            throw CommunityError.server(code: nil, message: "A community needs a name.")
        }
        return try await repository.create(draft)
    }
}

struct UpdateCommunityUseCase: UpdateCommunityUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func execute(
        communityId: String,
        name: String?,
        description: String?,
        image: String?
    ) async throws -> Community {
        try await repository.update(
            communityId: communityId,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description,
            image: image
        )
    }
}

struct DeleteCommunityUseCase: DeleteCommunityUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func execute(communityId: String) async throws {
        try await repository.delete(communityId: communityId)
    }
}

// MARK: - Membership

struct JoinCommunityUseCase: JoinCommunityUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func execute(communityId: String) async throws -> CommunityMembershipOutcome {
        guard !communityId.isEmpty else { throw CommunityError.notFound }
        return try await repository.join(communityId: communityId)
    }

    func execute(inviteCode: String) async throws -> CommunityMembershipOutcome {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw CommunityError.invalidInviteCode }
        return try await repository.join(inviteCode: code)
    }
}

struct LeaveCommunityUseCase: LeaveCommunityUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func execute(communityId: String) async throws -> CommunityMembershipOutcome {
        try await repository.leave(communityId: communityId)
    }
}

// MARK: - Members

struct ManageCommunityMembersUseCase: ManageCommunityMembersUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func add(communityId: String, userId: String, userName: String) async throws {
        guard !userId.isEmpty else { throw CommunityError.notFound }
        try await repository.addMember(
            communityId: communityId,
            userId: userId,
            userName: userName
        )
    }

    func remove(communityId: String, userId: String) async throws {
        try await repository.removeMember(communityId: communityId, userId: userId)
    }

    func updateRole(communityId: String, userId: String, role: CommunityRole) async throws {
        try await repository.updateRole(communityId: communityId, userId: userId, role: role)
    }

    func transferOwnership(communityId: String, newOwnerUserId: String) async throws {
        guard !newOwnerUserId.isEmpty else { throw CommunityError.notFound }
        try await repository.transferOwnership(
            communityId: communityId,
            newOwnerUserId: newOwnerUserId
        )
    }
}

// MARK: - Groups

struct ManageCommunityGroupsUseCase: ManageCommunityGroupsUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func groups(communityId: String) async throws -> [CommunityGroupSummary] {
        try await repository.groups(communityId: communityId)
    }

    func members(communityId: String, groupId: String) async throws -> [CommunityMember] {
        try await repository.groupMembers(communityId: communityId, groupId: groupId)
    }

    func attach(communityId: String, groupId: String) async throws {
        try await repository.linkGroup(communityId: communityId, groupId: groupId)
    }

    func join(communityId: String, groupId: String) async throws {
        guard !groupId.isEmpty else { throw CommunityError.groupNotInCommunity }
        try await repository.joinGroup(communityId: communityId, groupId: groupId)
    }

    func detach(communityId: String, groupId: String, isAnnouncementGroup: Bool) async throws {
        // Identity refuses this with CANNOT_DETACH_ANNOUNCEMENTS. Refusing it
        // here as well keeps a pointless round trip — and a confusing failure —
        // off a screen that already knows which group it is holding.
        guard !isAnnouncementGroup else { throw CommunityError.cannotDetachAnnouncements }
        try await repository.unlinkGroup(communityId: communityId, groupId: groupId)
    }
}

struct CommunitySettingsUseCase: CommunitySettingsUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func load(communityId: String) async throws -> CommunitySettings {
        try await repository.settings(communityId: communityId)
    }

    func save(communityId: String, settings: CommunitySettings) async throws {
        try await repository.updateSettings(communityId: communityId, settings: settings)
    }
}

// MARK: - Opening a conversation

struct OpenCommunityConversationUseCase: OpenCommunityConversationUseCaseProtocol {

    let repository: CommunityRepositoryProtocol

    func execute(communityId: String, groupId: String) async throws -> String {
        let groups = try await repository.groups(communityId: communityId)

        guard let group = groups.first(where: { $0.id == groupId }) else {
            throw CommunityError.groupNotInCommunity
        }
        guard let conversationId = group.conversationId, !conversationId.isEmpty else {
            // Identity committed the group but Core never created its
            // conversation — the gRPC call failed, and the doc's "Inbox vide"
            // row is exactly this.
            throw CommunityError.conversationNotProvisioned
        }
        return conversationId
    }
}
