//
//  RemoteCommunityDataSourceProtocol.swift
//  FeatureChat
//

import Foundation

/// Raw access to /identity/communities. Returns DTOs and throws `APIError`;
/// turning either into domain terms is the repository's job.
public protocol RemoteCommunityDataSourceProtocol {

    // Communities
    func createCommunity(_ request: CreateCommunityRequest) async throws -> CommunityDto
    func listCommunities(page: Int, size: Int) async throws -> [CommunityDto]
    func listMyCommunities(page: Int, size: Int) async throws -> [CommunityDto]
    func getCommunity(id: String) async throws -> CommunityDto
    func updateCommunity(_ request: UpdateCommunityRequest) async throws -> CommunityDto
    func deleteCommunity(_ request: CommunityIdRequest) async throws

    // Membership
    func changeMembership(_ request: CommunityMembershipRequest) async throws

    // Member administration
    func addMember(_ request: AddCommunityMemberRequest) async throws
    func removeMember(_ request: RemoveCommunityMemberRequest) async throws
    func updateMemberRole(_ request: UpdateCommunityMemberRoleRequest) async throws
    func transferOwner(_ request: TransferCommunityOwnerRequest) async throws

    // Groups
    func linkGroup(_ request: LinkCommunityGroupRequest) async throws
    func listGroups(communityId: String) async throws -> [CommunityGroupDto]
    func listGroupMembers(communityId: String, groupId: String) async throws -> [CommunityMemberDto]

    // Mocked in DEBUG until Identity exposes them.
    func settings(communityId: String) async throws -> CommunitySettingsDto
    func updateSettings(_ request: UpdateCommunitySettingsRequest) async throws
    func joinGroup(_ request: JoinCommunityGroupRequest) async throws
}
