//
//  CommunityRequests.swift
//  FeatureChat
//
//  Bodies for POST/PUT/DELETE on /identity/communities.
//

import Foundation

// MARK: - Create

/// `POST /communities`
///
/// Identity also creates the announcements group and makes the caller OWNER, so
/// neither is listed here.
public struct CreateCommunityRequest: Codable, Sendable {
    let name: String
    let description: String?
    let image: String?
    let isPrivate: Bool
    let existingGroupIds: [String]?
    let newGroups: [NewCommunityGroupRequest]?
}

public struct NewCommunityGroupRequest: Codable, Sendable {
    let name: String
    let description: String?
    /// Identity spells this one singular, and it is a list.
    let memberUserId: [String]
}

// MARK: - Update / delete

/// `PUT /communities`
public struct UpdateCommunityRequest: Codable, Sendable {
    let communityId: String
    let name: String?
    let description: String?
    let image: String?
}

/// `DELETE /communities/delete`, and the body for `GET /communities/byId`.
public struct CommunityIdRequest: Codable, Sendable {
    let communityId: String
}

// MARK: - Membership

/// `POST /communities/membership`
///
/// One body for three moves: join a public community by id, join a private one
/// by invite code, or leave.
public struct CommunityMembershipRequest: Codable, Sendable {

    let leave: Bool
    let communityId: String?
    let inviteCode: String?

    // Named `joining`/`leaving` because `leave` is already an instance property
    // on this type.

    static func joining(communityId: String) -> CommunityMembershipRequest {
        .init(leave: false, communityId: communityId, inviteCode: nil)
    }

    static func joining(inviteCode: String) -> CommunityMembershipRequest {
        .init(leave: false, communityId: nil, inviteCode: inviteCode)
    }

    static func leaving(communityId: String) -> CommunityMembershipRequest {
        .init(leave: true, communityId: communityId, inviteCode: nil)
    }
}

// MARK: - Member administration

/// `POST /communities/members/add`
public struct AddCommunityMemberRequest: Codable, Sendable {
    let communityId: String
    let userId: String
    let userName: String
}

/// `POST /communities/members/remove`
public struct RemoveCommunityMemberRequest: Codable, Sendable {
    let communityId: String
    let userId: String
}

/// `POST /communities/members/role`
public struct UpdateCommunityMemberRoleRequest: Codable, Sendable {
    let communityId: String
    let userId: String
    let role: String
}

/// `POST /communities/owner/transfer`
public struct TransferCommunityOwnerRequest: Codable, Sendable {
    let communityId: String
    let newOwnerUserId: String
}

// MARK: - Groups

/// `PUT /communities/settings` — mocked until Identity exposes it.
public struct UpdateCommunitySettingsRequest: Codable, Sendable {
    let communityId: String
    let whoCanAddMembers: String
    let whoCanAddGroups: String
}

/// `POST /communities/groups/join` — a member joining a sub-group themselves.
public struct JoinCommunityGroupRequest: Codable, Sendable {
    let communityId: String
    let groupId: String
}

/// `POST /communities/groups/link` — `attach: false` detaches.
public struct LinkCommunityGroupRequest: Codable, Sendable {
    let communityId: String
    let groupId: String
    let attach: Bool
}
