//
//  HTTPChannelDataSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

final class HTTPChannelDataSource: RemoteChannelDataSourceProtocol {

    private let httpClient: APIClientProtocol

    init(httpClient: APIClientProtocol) {
        self.httpClient = httpClient
    }

    func createChannel(_ request: CreateChannelRequest) async throws -> ChannelDto {
        let response: ChannelAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.create(request)
        )
        let dto = try payload(response)

        #if DEBUG
        // The server drops the description; keep the one the user typed so the
        // screens behave as they will once the field exists.
        if ChannelCommunityDebugConfiguration.useMockChannelDescription {
            ChannelCommunityDebugMockStore.setDescription(request.description, channelId: dto.id)
            return withMockedDescription(dto)
        }
        #endif

        return dto
    }

    func listChannels(page: Int, size: Int) async throws -> [ChannelDto] {
        let response: ChannelListAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.list(page: page, size: size)
        )
        return response.data ?? []
    }

    func getChannel(id: String) async throws -> ChannelDto {
        let response: ChannelAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.byId(channelId: id)
        )
        let dto = try payload(response)

        #if DEBUG
        if ChannelCommunityDebugConfiguration.useMockChannelDescription {
            return withMockedDescription(dto)
        }
        #endif

        return dto
    }

    func updateChannel(_ request: UpdateChannelRequest) async throws -> ChannelDto {
        #if DEBUG
        if ChannelCommunityDebugConfiguration.useMockChannelDescription,
           let description = request.description {
            ChannelCommunityDebugMockStore.setDescription(description, channelId: request.channelId)
        }
        #endif

        let response: ChannelAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.update(request)
        )
        let dto = try payload(response)

        #if DEBUG
        if ChannelCommunityDebugConfiguration.useMockChannelDescription {
            return withMockedDescription(dto)
        }
        #endif

        return dto
    }

    // MARK: - Admins

    func listAdmins(channelId: String) async throws -> [ChannelAdminDto] {
        #if DEBUG
        if ChannelCommunityDebugConfiguration.useMockChannelAdmins {
            return ChannelCommunityDebugMockStore.admins(channelId: channelId)
        }
        #endif

        let response: ChannelAdminListAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.admins(channelId: channelId)
        )
        return response.data ?? []
    }

    func addAdmin(_ request: ChannelAdminRequest) async throws {
        #if DEBUG
        if ChannelCommunityDebugConfiguration.useMockChannelAdmins {
            ChannelCommunityDebugMockStore.addAdmin(
                ChannelAdminDto(
                    userId: request.userId,
                    userName: request.userName,
                    avatar: nil,
                    addedAt: ISO8601DateFormatter().string(from: Date())
                ),
                channelId: request.channelId
            )
            return
        }
        #endif

        let _: ChannelMutationAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.addAdmin(request)
        )
    }

    func removeAdmin(_ request: ChannelAdminRequest) async throws {
        #if DEBUG
        if ChannelCommunityDebugConfiguration.useMockChannelAdmins {
            ChannelCommunityDebugMockStore.removeAdmin(
                userId: request.userId,
                channelId: request.channelId
            )
            return
        }
        #endif

        let _: ChannelMutationAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.removeAdmin(request)
        )
    }

    func changeSubscription(_ request: ChannelSubscriptionRequest) async throws {
        let _: ChannelMutationAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.subscription(request)
        )
    }

    // MARK: - Invite Links

    func generateInviteLink(_ request: GenerateChannelInviteLinkRequest) async throws -> ChannelInviteLinkDto {
        let response: ChannelInviteLinkAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.generateInviteLink(request)
        )
        return try payload(response)
    }

    func getInviteLink(channelId: String) async throws -> ChannelInviteLinkDto {
        let response: ChannelInviteLinkAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.getInviteLink(channelId: channelId)
        )
        return try payload(response)
    }

    func revokeInviteLink(_ request: RevokeChannelInviteLinkRequest) async throws {
        let _: ChannelMutationAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.revokeInviteLink(request)
        )
    }

    func joinByCode(_ request: JoinChannelByCodeRequest) async throws -> JoinChannelByCodeResponseDto {
        let response: JoinChannelByCodeAPIResponse = try await httpClient.request(
            endpoint: ChannelEndpoints.joinByCode(request)
        )
        return try payload(response)
    }

    #if DEBUG
    /// Rebuilds the DTO with the description the mock store is holding.
    private func withMockedDescription(_ dto: ChannelDto) -> ChannelDto {
        ChannelDto(
            id: dto.id,
            channelName: dto.channelName,
            name: dto.name,
            channelType: dto.channelType,
            image: dto.image,
            description: ChannelCommunityDebugMockStore.description(channelId: dto.id) ?? dto.description,
            conversationId: dto.conversationId,
            createdByUserId: dto.createdByUserId,
            subscriberCount: dto.subscriberCount,
            isSubscribed: dto.isSubscribed,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            subscriberIds: dto.subscriberIds
        )
    }
    #endif

    private func payload<T>(_ response: IdentityAPIResponse<T>) throws -> T {
        guard let data = response.data else {
            throw APIError.emptyResponse
        }
        return data
    }
}
