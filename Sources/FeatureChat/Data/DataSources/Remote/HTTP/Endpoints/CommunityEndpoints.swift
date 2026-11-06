//
//  CommunityEndpoints.swift
//  FeatureChat
//
//  /identity/communities — structure only. The conversations these communities
//  own are read from Projection and written to Core like any other.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

enum CommunityEndpoints {
    case create(CreateCommunityRequest)
    case list(page: Int, size: Int)
    case mine(page: Int, size: Int)
    case byId(communityId: String)
    case update(UpdateCommunityRequest)
    case delete(CommunityIdRequest)
    case membership(CommunityMembershipRequest)
    case addMember(AddCommunityMemberRequest)
    case removeMember(RemoveCommunityMemberRequest)
    case updateMemberRole(UpdateCommunityMemberRoleRequest)
    case transferOwner(TransferCommunityOwnerRequest)
    case linkGroup(LinkCommunityGroupRequest)
    case groups(communityId: String)
    case groupMembers(communityId: String, groupId: String)
    // Mocked in DEBUG until Identity exposes them.
    case settings(communityId: String)
    case updateSettings(UpdateCommunitySettingsRequest)
    case joinGroup(JoinCommunityGroupRequest)
}

extension CommunityEndpoints: APIEndpoint {

    var path: String {
        switch self {
        case .create, .list:
            return "/identity/communities"
        case .mine:
            return "/identity/communities/me"
        case .byId:
            return "/identity/communities/byId"
        case .update:
            return "/identity/communities"
        case .delete:
            return "/identity/communities/delete"
        case .membership:
            return "/identity/communities/membership"
        case .addMember:
            return "/identity/communities/members/add"
        case .removeMember:
            return "/identity/communities/members/remove"
        case .updateMemberRole:
            return "/identity/communities/members/role"
        case .transferOwner:
            return "/identity/communities/owner/transfer"
        case .linkGroup:
            return "/identity/communities/groups/link"
        case .groups:
            return "/identity/communities/groups"
        case .groupMembers:
            return "/identity/communities/groups/members"
        case .settings, .updateSettings:
            return "/identity/communities/settings"
        case .joinGroup:
            return "/identity/communities/groups/join"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .list, .mine, .byId, .groups, .groupMembers, .settings:
            return .get
        case .create, .membership, .addMember, .removeMember, .updateMemberRole,
                .transferOwner, .linkGroup, .joinGroup:
            return .post
        case .update, .updateSettings:
            return .put
        case .delete:
            return .delete
        }
    }

    var parameters: [String: Any]? {
        switch self {
        case .create(let request):
            return try? request.toDictionary()
        case .update(let request):
            return try? request.toDictionary()
        case .delete(let request):
            return try? request.toDictionary()
        case .membership(let request):
            return try? request.toDictionary()
        case .addMember(let request):
            return try? request.toDictionary()
        case .removeMember(let request):
            return try? request.toDictionary()
        case .updateMemberRole(let request):
            return try? request.toDictionary()
        case .transferOwner(let request):
            return try? request.toDictionary()
        case .linkGroup(let request):
            return try? request.toDictionary()

        case .list(let page, let size), .mine(let page, let size):
            return ["page": page, "size": size]

        // The integration doc writes this one as a GET carrying a JSON body.
        // A body on GET is dropped by most proxies and cannot be expressed by
        // this client — parameters on GET become query items — so the id is
        // sent as a query parameter instead.
        case .byId(let communityId):
            return ["communityId": communityId]

        case .groups(let communityId):
            return ["communityId": communityId]
        case .groupMembers(let communityId, let groupId):
            return ["communityId": communityId, "groupId": groupId]
        case .settings(let communityId):
            return ["communityId": communityId]
        case .updateSettings(let request):
            return try? request.toDictionary()
        case .joinGroup(let request):
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

extension CommunityEndpoints: EndpointPolicyProviding {

    var cachePolicy: EndpointCachePolicy { .noCache }

    var circuitBreakerProfile: CircuitBreakerProfile { .standard }

    var priority: RequestPriority { .medium }

    var timeoutPolicy: EndpointTimeoutPolicy { .standard }

    var isIdempotent: Bool {
        switch self {
        case .list, .mine, .byId, .groups, .groupMembers, .settings:
            return true
        case .create, .update, .delete, .membership, .addMember, .removeMember,
                .updateMemberRole, .transferOwner, .linkGroup, .updateSettings,
                .joinGroup:
            return false
        }
    }

    var rateLimitPolicy: RateLimitPolicy { .standard }
}
