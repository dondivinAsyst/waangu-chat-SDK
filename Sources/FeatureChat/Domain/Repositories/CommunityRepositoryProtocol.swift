//
//  CommunityRepositoryProtocol.swift
//  FeatureChat
//

import Foundation

/// Communities as the domain sees them.
///
/// Failures are reported as `CommunityError` — never as a transport error.
protocol CommunityRepositoryProtocol {

    /// Communities this user belongs to, groups and members included.
    /// - Parameter refresh: `false` answers from the last fetch when there is one.
    func myCommunities(refresh: Bool) async throws -> [Community]

    /// Public directory, for joining something new.
    func discoverCommunities(page: Int, size: Int) async throws -> [Community]

    func community(id: String) async throws -> Community

    func create(_ draft: NewCommunityDraft) async throws -> Community

    func update(
        communityId: String,
        name: String?,
        description: String?,
        image: String?
    ) async throws -> Community

    func delete(communityId: String) async throws

    // MARK: Membership

    func join(communityId: String) async throws -> CommunityMembershipOutcome
    func join(inviteCode: String) async throws -> CommunityMembershipOutcome
    func leave(communityId: String) async throws -> CommunityMembershipOutcome

    // MARK: Member administration

    func addMember(communityId: String, userId: String, userName: String) async throws
    func removeMember(communityId: String, userId: String) async throws
    func updateRole(communityId: String, userId: String, role: CommunityRole) async throws
    func transferOwnership(communityId: String, newOwnerUserId: String) async throws

    /// The community group a conversation belongs to, with the role this user
    /// holds in that community. Nil when the conversation is not a community's.
    ///
    /// Read from what `myCommunities` already fetched — a room the user is in
    /// belongs to a community they are in.
    func groupContext(
        forConversationId conversationId: String
    ) async throws -> (community: Community, group: CommunityGroupSummary)?

    // MARK: Groups

    func groups(communityId: String) async throws -> [CommunityGroupSummary]
    func groupMembers(communityId: String, groupId: String) async throws -> [CommunityMember]
    /// Permissions. Mocked until Identity exposes `/communities/settings`.
    func settings(communityId: String) async throws -> CommunitySettings
    func updateSettings(communityId: String, settings: CommunitySettings) async throws

    /// A member joining a sub-group themselves.
    func joinGroup(communityId: String, groupId: String) async throws

    func linkGroup(communityId: String, groupId: String) async throws
    func unlinkGroup(communityId: String, groupId: String) async throws
}
