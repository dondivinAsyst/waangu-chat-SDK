//
//  RemoteChannelDataSourceProtocol.swift
//  FeatureChat
//

import Foundation

/// Raw access to /identity/channels. Returns DTOs and throws `APIError`.
public protocol RemoteChannelDataSourceProtocol {
    func createChannel(_ request: CreateChannelRequest) async throws -> ChannelDto
    func listChannels(page: Int, size: Int) async throws -> [ChannelDto]
    func getChannel(id: String) async throws -> ChannelDto
    func updateChannel(_ request: UpdateChannelRequest) async throws -> ChannelDto
    func changeSubscription(_ request: ChannelSubscriptionRequest) async throws

    // Mocked in DEBUG until Identity exposes them.
    func listAdmins(channelId: String) async throws -> [ChannelAdminDto]
    func addAdmin(_ request: ChannelAdminRequest) async throws
    func removeAdmin(_ request: ChannelAdminRequest) async throws
    
    // MARK: - Invite Links
    /// Generate or regenerate a shareable invite link for a channel
    func generateInviteLink(_ request: GenerateChannelInviteLinkRequest) async throws -> ChannelInviteLinkDto
    /// Get the current invite link for a channel
    func getInviteLink(channelId: String) async throws -> ChannelInviteLinkDto
    /// Revoke the current invite link, making it invalid
    func revokeInviteLink(_ request: RevokeChannelInviteLinkRequest) async throws
    /// Join a channel using an invite code
    func joinByCode(_ request: JoinChannelByCodeRequest) async throws -> JoinChannelByCodeResponseDto
}
