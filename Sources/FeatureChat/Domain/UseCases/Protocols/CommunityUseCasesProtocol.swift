//
//  CommunityUseCasesProtocol.swift
//  FeatureChat
//

import Foundation

// MARK: - Reading

public protocol ListMyCommunitiesUseCaseProtocol {
    /// - Parameter refresh: `false` accepts the last read.
    func execute(refresh: Bool) async throws -> [Community]
}

public protocol DiscoverCommunitiesUseCaseProtocol {
    func execute(page: Int, size: Int) async throws -> [Community]
}

public protocol GetCommunityUseCaseProtocol {
    func execute(communityId: String) async throws -> Community
}

// MARK: - Writing

public protocol CreateCommunityUseCaseProtocol {
    func execute(_ draft: NewCommunityDraft) async throws -> Community
}

public protocol UpdateCommunityUseCaseProtocol {
    func execute(
        communityId: String,
        name: String?,
        description: String?,
        image: String?
    ) async throws -> Community
}

public protocol DeleteCommunityUseCaseProtocol {
    func execute(communityId: String) async throws
}

// MARK: - Membership

public protocol JoinCommunityUseCaseProtocol {
    /// Public community.
    func execute(communityId: String) async throws -> CommunityMembershipOutcome
    /// Private community — the code is the only way in.
    func execute(inviteCode: String) async throws -> CommunityMembershipOutcome
}

public protocol LeaveCommunityUseCaseProtocol {
    func execute(communityId: String) async throws -> CommunityMembershipOutcome
}

// MARK: - Members

public protocol ManageCommunityMembersUseCaseProtocol {
    func add(communityId: String, userId: String, userName: String) async throws
    func remove(communityId: String, userId: String) async throws
    func updateRole(communityId: String, userId: String, role: CommunityRole) async throws
    func transferOwnership(communityId: String, newOwnerUserId: String) async throws
}

// MARK: - Groups

/// A community's permissions. Mocked until Identity exposes them.
public protocol CommunitySettingsUseCaseProtocol {
    func load(communityId: String) async throws -> CommunitySettings
    func save(communityId: String, settings: CommunitySettings) async throws
}

public protocol ManageCommunityGroupsUseCaseProtocol {
    func groups(communityId: String) async throws -> [CommunityGroupSummary]
    func members(communityId: String, groupId: String) async throws -> [CommunityMember]
    func attach(communityId: String, groupId: String) async throws
    /// A member joining a sub-group themselves — community membership is not
    /// group membership, so this is its own step.
    func join(communityId: String, groupId: String) async throws
    /// Throws `CommunityError.cannotDetachAnnouncements` for the announcements
    /// group without going to the network.
    func detach(communityId: String, groupId: String, isAnnouncementGroup: Bool) async throws
}

// MARK: - Opening a conversation

/// Resolves the conversation a community group is chatted in.
///
/// Kept apart from the group listing because the failure it reports —
/// `conversationNotProvisioned` — is the one the screens actually have to
/// handle: Identity created the group, Core has not created its conversation
/// yet, and there is nothing to open.
public protocol OpenCommunityConversationUseCaseProtocol {
    func execute(communityId: String, groupId: String) async throws -> String
}

// MARK: - Container

public protocol CommunityUseCasesProtocol {
    var listMine: ListMyCommunitiesUseCaseProtocol { get }
    var discover: DiscoverCommunitiesUseCaseProtocol { get }
    var getCommunity: GetCommunityUseCaseProtocol { get }
    var createCommunity: CreateCommunityUseCaseProtocol { get }
    var updateCommunity: UpdateCommunityUseCaseProtocol { get }
    var deleteCommunity: DeleteCommunityUseCaseProtocol { get }
    var joinCommunity: JoinCommunityUseCaseProtocol { get }
    var leaveCommunity: LeaveCommunityUseCaseProtocol { get }
    var manageMembers: ManageCommunityMembersUseCaseProtocol { get }
    var manageGroups: ManageCommunityGroupsUseCaseProtocol { get }
    var settings: CommunitySettingsUseCaseProtocol { get }
    var openConversation: OpenCommunityConversationUseCaseProtocol { get }
}
