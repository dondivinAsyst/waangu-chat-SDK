//
//  CommunityResponseDto.swift
//  FeatureChat
//
//  What /identity/communities returns.
//

import Foundation

// MARK: - Community

/// Timestamps stay `String` and are parsed in the mapper: the shared decoder is
/// set to strict `.iso8601`, which rejects the fractional seconds this backend
/// sends, and one unparseable date must not cost the whole community.
public struct CommunityDto: Decodable {

    let id: String
    let name: String?
    let description: String?
    let image: String?
    let isPrivate: Bool?
    let inviteCode: String?
    let announcementGroupId: String?
    let memberCount: Int?
    let maxMembers: Int?

    /// This user's rank. Identity has spelled it both ways depending on route.
    let myRole: String?
    let role: String?

    let groups: [CommunityGroupDto]?
    let members: [CommunityMemberDto]?

    let createdAt: String?
    let updatedAt: String?
}

// MARK: - Group inside a community

public struct CommunityGroupDto: Decodable {

    let id: String
    let name: String?
    let description: String?
    let image: String?
    let isAnnouncementGroup: Bool?

    /// Core conversation carried by the `Group` entity. Absent until Identity's
    /// gRPC `CreateConversation` has landed.
    let conversationId: String?

    let memberCount: Int?
    let members: [CommunityMemberDto]?
}

// MARK: - Member

public struct CommunityMemberDto: Decodable {

    let userId: String?
    /// Some routes key the member row by its own id and put the account id in
    /// `userId`; when only one is present it is the account id.
    let id: String?
    let userName: String?
    let name: String?
    let avatar: String?
    let phone: String?
    let role: String?
    let joinedAt: String?

    /// Account id, whichever field carried it.
    var resolvedUserId: String? {
        let candidate = userId ?? id
        guard let candidate, !candidate.isEmpty else { return nil }
        return candidate
    }

    var resolvedName: String {
        userName ?? name ?? ""
    }
}

// MARK: - Envelopes

/// Who may add members and groups. Served from the debug mock store until
/// Identity exposes `/communities/settings`.
public struct CommunitySettingsDto: Codable {
    let communityId: String
    let whoCanAddMembers: String?
    let whoCanAddGroups: String?
}

public typealias CommunityAPIResponse = IdentityAPIResponse<CommunityDto>
public typealias CommunitySettingsAPIResponse = IdentityAPIResponse<CommunitySettingsDto>
public typealias CommunityListAPIResponse = IdentityAPIResponse<[CommunityDto]>
public typealias CommunityGroupListAPIResponse = IdentityAPIResponse<[CommunityGroupDto]>
public typealias CommunityMemberListAPIResponse = IdentityAPIResponse<[CommunityMemberDto]>
/// Mutation routes answer with the envelope and no payload.
public typealias CommunityMutationAPIResponse = IdentityAPIResponse<EmptyIdentityPayload>

/// Stands in for `data` on routes that carry nothing useful in it.
public struct EmptyIdentityPayload: Decodable {
    public init(from decoder: Decoder) throws {}
}
