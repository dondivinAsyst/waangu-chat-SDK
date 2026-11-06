//
//  ChannelEndpoints.swift
//  FeatureChat
//
//  /identity/channels — canaux Updates. A channel is standalone: it is not
//  attached to a community, and its messages live in one Core BROADCAST
//  conversation.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

enum ChannelEndpoints {
    case create(CreateChannelRequest)
    case list(page: Int, size: Int)
    case byId(channelId: String)
    case update(UpdateChannelRequest)
    case subscription(ChannelSubscriptionRequest)
    // Mocked in DEBUG until Identity exposes them — the routes are written as
    // they are expected to land, so switching is a flag flip.
    case admins(channelId: String)
    case addAdmin(ChannelAdminRequest)
    case removeAdmin(ChannelAdminRequest)
    
    // MARK: - Invite Link Endpoints
    /// Generate or regenerate a shareable invite link for a channel
    case generateInviteLink(GenerateChannelInviteLinkRequest)
    /// Get the current invite link for a channel
    case getInviteLink(channelId: String)
    /// Revoke the current invite link for a channel
    case revokeInviteLink(RevokeChannelInviteLinkRequest)
    /// Join a channel using an invite code
    case joinByCode(JoinChannelByCodeRequest)
}

extension ChannelEndpoints: APIEndpoint {

    var path: String {
        switch self {
        case .create, .list, .update:
            return "/identity/channels"
        case .byId:
            return "/identity/channels/byId"
        case .subscription:
            return "/identity/channels/subscription"
        case .admins, .addAdmin:
            return "/identity/channels/admins"
        case .removeAdmin:
            return "/identity/channels/admins/remove"
        case .generateInviteLink(let request):
            return "/identity/channels/\(request.channelId)/invite-link"
        case .getInviteLink(let channelId):
            return "/identity/channels/\(channelId)/invite-link"
        case .revokeInviteLink(let request):
            return "/identity/channels/\(request.channelId)/invite-link"
        case .joinByCode:
            return "/identity/channels/join-by-code"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .list, .byId, .admins, .getInviteLink:
            return .get
        case .create, .subscription, .addAdmin, .removeAdmin, .generateInviteLink, .joinByCode:
            return .post
        case .update:
            return .put
        case .revokeInviteLink:
            return .delete
        }
    }

    var parameters: [String: Any]? {
        switch self {
        case .create(let request):
            return try? request.toDictionary()
        case .update(let request):
            return try? request.toDictionary()
        case .subscription(let request):
            return try? request.toDictionary()
        case .list(let page, let size):
            return ["page": page, "size": size]
        case .byId(let channelId):
            return ["channelId": channelId]
        case .admins(let channelId):
            return ["channelId": channelId]
        case .addAdmin(let request), .removeAdmin(let request):
            return try? request.toDictionary()
        case .generateInviteLink(let request):
            return try? request.toDictionary()
        case .getInviteLink(let channelId):
            return ["channelId": channelId]
        case .revokeInviteLink(let request):
            return try? request.toDictionary()
        case .joinByCode(let request):
            return try? request.toDictionary()
        }
    }

    var headers: [String: String]? {
        [
            "X-Correlation-Id": CorrelationId().value,  // B59 — même règle que ChatFinanceEndpoints
            "Content-Type": "application/json",
            "Accept": "application/json",
            "x-chat-session": CurrentSessionInfo.shared.sessionId
        ]
    }
}

extension ChannelEndpoints: EndpointPolicyProviding {

    var cachePolicy: EndpointCachePolicy { .noCache }

    var circuitBreakerProfile: CircuitBreakerProfile { .standard }

    var priority: RequestPriority { .medium }

    var timeoutPolicy: EndpointTimeoutPolicy { .standard }

    var isIdempotent: Bool {
        switch self {
        case .list, .byId, .admins, .getInviteLink:
            return true
        case .create, .update, .subscription, .addAdmin, .removeAdmin, .generateInviteLink, .revokeInviteLink, .joinByCode:
            return false
        }
    }

    var rateLimitPolicy: RateLimitPolicy { .standard }
}
