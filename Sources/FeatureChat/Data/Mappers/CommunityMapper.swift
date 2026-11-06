//
//  CommunityMapper.swift
//  FeatureChat
//
//  Community DTOs ↔ entities, and Identity's error names → CommunityError.
//

import Foundation
import WaanguNetworkKit

enum CommunityMapper {

    // MARK: - DTO → Entity

    static func toDomain(_ dto: CommunityDto) -> Community {
        let groups = (dto.groups ?? []).map { toDomain($0) }

        return Community(
            id: dto.id,
            name: dto.name ?? "",
            description: dto.description,
            image: dto.image,
            isPrivate: dto.isPrivate ?? false,
            inviteCode: dto.inviteCode,
            announcementGroupId: dto.announcementGroupId ?? groups.first(where: { $0.isAnnouncementGroup })?.id,
            memberCount: dto.memberCount ?? 0,
            maxMembers: dto.maxMembers ?? Community.defaultMaxMembers,
            myRole: role(from: dto.myRole ?? dto.role),
            groups: sortedAnnouncementsFirst(groups),
            createdAt: ISO8601Timestamp.date(from: dto.createdAt),
            updatedAt: ISO8601Timestamp.date(from: dto.updatedAt)
        )
    }

    static func toDomain(_ dto: CommunityGroupDto) -> CommunityGroupSummary {
        let members = (dto.members ?? []).compactMap { toDomain($0) }

        return CommunityGroupSummary(
            id: dto.id,
            name: dto.name ?? "",
            description: dto.description,
            image: dto.image,
            isAnnouncementGroup: dto.isAnnouncementGroup ?? false,
            conversationId: dto.conversationId,
            memberCount: dto.memberCount ?? members.count,
            members: members
        )
    }

    /// Nil when the row carries no account id — a member this app cannot address
    /// is not a member it can show.
    static func toDomain(_ dto: CommunityMemberDto) -> CommunityMember? {
        guard let userId = dto.resolvedUserId else { return nil }

        return CommunityMember(
            userId: userId,
            userName: dto.resolvedName,
            avatar: dto.avatar,
            phone: dto.phone,
            role: role(from: dto.role) ?? .member,
            joinedAt: ISO8601Timestamp.date(from: dto.joinedAt)
        )
    }

    /// Identity returns announcements first on `/communities/me`; the other
    /// routes do not promise it, so the order is applied here once.
    static func sortedAnnouncementsFirst(_ groups: [CommunityGroupSummary]) -> [CommunityGroupSummary] {
        groups.sorted { lhs, rhs in
            if lhs.isAnnouncementGroup != rhs.isAnnouncementGroup {
                return lhs.isAnnouncementGroup
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func toDomain(_ dto: CommunitySettingsDto) -> CommunitySettings {
        CommunitySettings(
            whoCanAddMembers: permission(from: dto.whoCanAddMembers) ?? .adminsOnly,
            whoCanAddGroups: permission(from: dto.whoCanAddGroups) ?? .everyone
        )
    }

    private static func permission(from raw: String?) -> CommunityPermission? {
        guard let raw, !raw.isEmpty else { return nil }
        return CommunityPermission(rawValue: raw.uppercased())
    }

    private static func role(from raw: String?) -> CommunityRole? {
        guard let raw, !raw.isEmpty else { return nil }
        return CommunityRole(rawValue: raw.uppercased())
    }

    // MARK: - Entity → Request

    static func toRequest(_ draft: NewCommunityDraft) -> CreateCommunityRequest {
        CreateCommunityRequest(
            name: draft.name,
            description: draft.description,
            image: draft.image,
            isPrivate: draft.isPrivate,
            // Both group fields stay on the request — they are part of the
            // documented contract — but nothing populates them: groups are added
            // to a community after it exists. See `NewCommunityDraft`.
            existingGroupIds: nil,
            newGroups: nil
        )
    }
}

// MARK: - Errors

enum CommunityErrorMapper {

    /// Identity names its refusals in `message`, which the API client keeps on
    /// `clientError`. A 403 arrives without a body, so it stays `.forbidden`
    /// rather than being guessed at.
    static func map(_ error: Error) -> CommunityError {
        if let community = error as? CommunityError { return community }

        guard let apiError = error as? APIError else {
            return .server(code: nil, message: error.localizedDescription)
        }

        switch apiError {
        case .notFound:
            return .notFound
        case .forbidden, .unauthorized:
            return .forbidden
        case .badRequest(let message):
            return named(message) ?? .server(code: nil, message: message)
        case .clientError(_, let message):
            return named(message) ?? .server(code: nil, message: message)
        default:
            return .server(code: nil, message: apiError.errorDescription)
        }
    }

    /// The documented error names, matched anywhere in the message: Identity
    /// sometimes sends the bare code and sometimes a sentence containing it.
    private static func named(_ message: String?) -> CommunityError? {
        guard let message, !message.isEmpty else { return nil }
        let upper = message.uppercased()

        if upper.contains("ALREADY_MEMBER") { return .alreadyMember }
        if upper.contains("PRIVATE_COMMUNITY") { return .privateCommunityRequiresInviteCode }
        if upper.contains("INVALID_INVITE") || upper.contains("INVITE_CODE") { return .invalidInviteCode }
        if upper.contains("COMMUNITY_FULL") { return .full(maxMembers: Community.defaultMaxMembers) }
        if upper.contains("CANNOT_DETACH_ANNOUNCEMENTS") { return .cannotDetachAnnouncements }
        if upper.contains("GROUP_NOT_IN_COMMUNITY") { return .groupNotInCommunity }
        if upper.contains("NOT_FOUND") { return .notFound }

        return nil
    }
}
