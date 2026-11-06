//
//  HTTPCommunityDataSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

final class HTTPCommunityDataSource: RemoteCommunityDataSourceProtocol {

    private let httpClient: APIClientProtocol

    init(httpClient: APIClientProtocol) {
        self.httpClient = httpClient
    }

    // MARK: - Communities

    func createCommunity(_ request: CreateCommunityRequest) async throws -> CommunityDto {
        let response: CommunityAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.create(request)
        )
        return try payload(response)
    }

    func listCommunities(page: Int, size: Int) async throws -> [CommunityDto] {
        let response: CommunityListAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.list(page: page, size: size)
        )
        return response.data ?? []
    }

    func listMyCommunities(page: Int, size: Int) async throws -> [CommunityDto] {
        let response: CommunityListAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.mine(page: page, size: size)
        )
        return response.data ?? []
    }

    func getCommunity(id: String) async throws -> CommunityDto {
        let response: CommunityAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.byId(communityId: id)
        )
        return try payload(response)
    }

    func updateCommunity(_ request: UpdateCommunityRequest) async throws -> CommunityDto {
        let response: CommunityAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.update(request)
        )
        return try payload(response)
    }

    func deleteCommunity(_ request: CommunityIdRequest) async throws {
        let _: CommunityMutationAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.delete(request)
        )
    }

    // MARK: - Membership

    func changeMembership(_ request: CommunityMembershipRequest) async throws {
        let _: CommunityMutationAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.membership(request)
        )
    }

    // MARK: - Member administration

    func addMember(_ request: AddCommunityMemberRequest) async throws {
        let _: CommunityMutationAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.addMember(request)
        )
    }

    func removeMember(_ request: RemoveCommunityMemberRequest) async throws {
        let _: CommunityMutationAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.removeMember(request)
        )
    }

    func updateMemberRole(_ request: UpdateCommunityMemberRoleRequest) async throws {
        let _: CommunityMutationAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.updateMemberRole(request)
        )
    }

    func transferOwner(_ request: TransferCommunityOwnerRequest) async throws {
        let _: CommunityMutationAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.transferOwner(request)
        )
    }

    // MARK: - Groups

    func linkGroup(_ request: LinkCommunityGroupRequest) async throws {
        let _: CommunityMutationAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.linkGroup(request)
        )
    }

    func listGroups(communityId: String) async throws -> [CommunityGroupDto] {
        let response: CommunityGroupListAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.groups(communityId: communityId)
        )
        return response.data ?? []
    }

    func listGroupMembers(communityId: String, groupId: String) async throws -> [CommunityMemberDto] {
        let response: CommunityMemberListAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.groupMembers(communityId: communityId, groupId: groupId)
        )
        return response.data ?? []
    }

    // MARK: - Settings and sub-group membership
    //
    // Mocked in DEBUG: Identity has no `/communities/settings` and no
    // self-service group join. The calls below are written as the real ones, so
    // clearing the flags in `ChannelCommunityDebugConfiguration` is the whole
    // switch-over.

    func settings(communityId: String) async throws -> CommunitySettingsDto {
        #if DEBUG
        if ChannelCommunityDebugConfiguration.useMockCommunitySettings {
            return ChannelCommunityDebugMockStore.settings(communityId: communityId)
        }
        #endif

        let response: CommunitySettingsAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.settings(communityId: communityId)
        )
        return try payload(response)
    }

    func updateSettings(_ request: UpdateCommunitySettingsRequest) async throws {
        #if DEBUG
        if ChannelCommunityDebugConfiguration.useMockCommunitySettings {
            ChannelCommunityDebugMockStore.updateSettings(
                CommunitySettingsDto(
                    communityId: request.communityId,
                    whoCanAddMembers: request.whoCanAddMembers,
                    whoCanAddGroups: request.whoCanAddGroups
                )
            )
            return
        }
        #endif

        let _: CommunityMutationAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.updateSettings(request)
        )
    }

    func joinGroup(_ request: JoinCommunityGroupRequest) async throws {
        #if DEBUG
        if ChannelCommunityDebugConfiguration.useMockCommunityGroupJoin {
            ChannelCommunityDebugMockStore.joinGroup(
                communityId: request.communityId,
                groupId: request.groupId
            )
            return
        }
        #endif

        let _: CommunityMutationAPIResponse = try await httpClient.request(
            endpoint: CommunityEndpoints.joinGroup(request)
        )
    }

    // MARK: - Private

    /// A 2xx envelope with no `data` on a route that is supposed to return one
    /// is a broken response, not an empty result.
    private func payload<T>(_ response: IdentityAPIResponse<T>) throws -> T {
        guard let data = response.data else {
            throw APIError.emptyResponse
        }
        return data
    }
}
