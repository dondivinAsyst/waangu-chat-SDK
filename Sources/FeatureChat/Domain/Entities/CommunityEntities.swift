//
//  CommunityEntities.swift
//  FeatureChat
//
//  Communities — Identity owns the structure, Core owns the conversations.
//

import Foundation

// MARK: - Community Role

/// Rank inside a community. Identity sends these uppercased.
public enum CommunityRole: String, Codable, Sendable, CaseIterable {
    case owner = "OWNER"
    case admin = "ADMIN"
    case moderator = "MODERATOR"
    case member = "MEMBER"

    /// Can edit the community, manage members and link groups.
    public var canAdminister: Bool {
        self == .owner || self == .admin
    }

    /// Can post in the announcements group. Everyone else reads it.
    public var canPostToAnnouncements: Bool {
        canAdminister
    }
}

// MARK: - Community

/// A community and the groups hanging off it.
///
/// Identity creates the announcements group with the community itself, and keeps
/// it in `groups` first — the same order `GET /communities/me` returns.
public struct Community: Identifiable, Equatable, Sendable {

    public let id: String
    public var name: String
    public var description: String?
    public var image: String?
    public var isPrivate: Bool

    /// Only handed out to members; joining a private community needs it.
    public var inviteCode: String?

    /// Group that carries the announcements conversation.
    public var announcementGroupId: String?

    public var memberCount: Int
    public var maxMembers: Int

    /// This user's rank, or nil when they are not a member.
    public var myRole: CommunityRole?

    public var groups: [CommunityGroupSummary]

    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        image: String? = nil,
        isPrivate: Bool = false,
        inviteCode: String? = nil,
        announcementGroupId: String? = nil,
        memberCount: Int = 0,
        maxMembers: Int = Community.defaultMaxMembers,
        myRole: CommunityRole? = nil,
        groups: [CommunityGroupSummary] = [],
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.image = image
        self.isPrivate = isPrivate
        self.inviteCode = inviteCode
        self.announcementGroupId = announcementGroupId
        self.memberCount = memberCount
        self.maxMembers = maxMembers
        self.myRole = myRole
        self.groups = groups
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Identity's ceiling when it does not send one.
    public static let defaultMaxMembers = 5000

    public var isMember: Bool { myRole != nil }

    public var isFull: Bool { memberCount >= maxMembers }

    public var announcementGroup: CommunityGroupSummary? {
        groups.first { $0.isAnnouncementGroup }
    }

    /// Sub-groups, announcements excluded — those are chatted in, not broadcast.
    public var chatGroups: [CommunityGroupSummary] {
        groups.filter { !$0.isAnnouncementGroup }
    }
}

// MARK: - Community Group

/// A group attached to a community, as the community screens need it.
///
/// Deliberately not `GroupChat`: that entity carries local sync state and is
/// owned by the groups feature. This is the read-only summary Identity returns
/// with a community.
public struct CommunityGroupSummary: Identifiable, Equatable, Sendable {

    public let id: String
    public var name: String
    public var description: String?
    public var image: String?

    /// The community's announcements group. Cannot be detached.
    public var isAnnouncementGroup: Bool

    /// Core conversation to open.
    ///
    /// Nil while Identity's gRPC `CreateConversation` has not landed — the group
    /// exists but there is nothing to open yet.
    public var conversationId: String?

    public var memberCount: Int
    public var members: [CommunityMember]

    public init(
        id: String,
        name: String,
        description: String? = nil,
        image: String? = nil,
        isAnnouncementGroup: Bool = false,
        conversationId: String? = nil,
        memberCount: Int = 0,
        members: [CommunityMember] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.image = image
        self.isAnnouncementGroup = isAnnouncementGroup
        self.conversationId = conversationId
        self.memberCount = memberCount
        self.members = members
    }

    public var isOpenable: Bool {
        !(conversationId ?? "").isEmpty
    }

    /// Who may send into this group's conversation.
    ///
    /// Announcements is read-only for everyone below admin; a normal sub-group
    /// is a plain chat, so membership is the only gate and it is enforced by
    /// Core, not here.
    public func canWrite(as role: CommunityRole?) -> Bool {
        guard isAnnouncementGroup else { return true }
        return role?.canPostToAnnouncements ?? false
    }
}

// MARK: - Community Member

public struct CommunityMember: Identifiable, Equatable, Sendable {

    public let userId: String
    public var userName: String
    public var avatar: String?
    public var phone: String?
    public var role: CommunityRole
    public var joinedAt: Date?

    public init(
        userId: String,
        userName: String,
        avatar: String? = nil,
        phone: String? = nil,
        role: CommunityRole = .member,
        joinedAt: Date? = nil
    ) {
        self.userId = userId
        self.userName = userName
        self.avatar = avatar
        self.phone = phone
        self.role = role
        self.joinedAt = joinedAt
    }

    public var id: String { userId }
}

// MARK: - Membership Outcome

/// What a join or leave actually did.
///
/// `alreadyMember` is a success, not a failure: Identity answers `ALREADY_MEMBER`
/// when the user is in the community already, and the screen should land them in
/// it rather than show an error.
public enum CommunityMembershipOutcome: Equatable, Sendable {
    case joined(communityId: String)
    case alreadyMember(communityId: String)
    case left(communityId: String)
}

// MARK: - Draft

/// What the create-community screen collects.
///
/// Groups are not part of it. `POST /communities` can create them in the same
/// call, but a group made that way has only a name — no members, no photo, no
/// settings — while the community screen's "Add group" runs the app's real group
/// flow and then links the result. One good path beats two, one of which makes
/// second-class groups. The announcements group is Identity's own doing either
/// way.
public struct NewCommunityDraft: Equatable, Sendable {

    public var name: String
    public var description: String?
    public var image: String?
    public var isPrivate: Bool

    public init(
        name: String,
        description: String? = nil,
        image: String? = nil,
        isPrivate: Bool = false
    ) {
        self.name = name
        self.description = description
        self.image = image
        self.isPrivate = isPrivate
    }
}


// MARK: - Settings

/// Who is allowed to do a thing in a community.
public enum CommunityPermission: String, Codable, Sendable, CaseIterable {
    case everyone = "EVERYONE"
    case adminsOnly = "ADMINS"
}

/// A community's permissions. Mocked locally until Identity exposes them.
public struct CommunitySettings: Equatable, Sendable {

    public var whoCanAddMembers: CommunityPermission
    public var whoCanAddGroups: CommunityPermission

    public init(
        whoCanAddMembers: CommunityPermission = .adminsOnly,
        whoCanAddGroups: CommunityPermission = .everyone
    ) {
        self.whoCanAddMembers = whoCanAddMembers
        self.whoCanAddGroups = whoCanAddGroups
    }
}

// MARK: - Errors

/// Failures the communities API reports by name, plus the ones this client can
/// tell apart on its own.
public enum CommunityError: Error, Equatable, Sendable {

    /// Already in the community. Callers that join should treat this as success.
    case alreadyMember
    /// Private community joined without an invite code.
    case privateCommunityRequiresInviteCode
    case invalidInviteCode
    case full(maxMembers: Int)
    case cannotDetachAnnouncements
    case groupNotInCommunity
    case notFound
    case forbidden

    /// Identity committed, but Core never got the participant, so the
    /// conversation this screen wants to open does not exist yet.
    case conversationNotProvisioned

    /// Anything else Identity reported, kept verbatim so it can be logged.
    case server(code: String?, message: String?)
}

extension CommunityError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .alreadyMember:
            return "You are already a member of this community."
        case .privateCommunityRequiresInviteCode:
            return "This community is private. An invite code is required."
        case .invalidInviteCode:
            return "This invite code is not valid."
        case .full(let maxMembers):
            return "This community is full (\(maxMembers) members)."
        case .cannotDetachAnnouncements:
            return "The announcements group cannot be detached."
        case .groupNotInCommunity:
            return "This group does not belong to this community."
        case .notFound:
            return "This community no longer exists."
        case .forbidden:
            return "You are not allowed to do this."
        case .conversationNotProvisioned:
            return "This conversation is not ready yet. Try again in a moment."
        case .server(let code, let message):
            return message ?? code ?? "The community service is unavailable."
        }
    }
}
