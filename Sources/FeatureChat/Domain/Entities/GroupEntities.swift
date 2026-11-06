import Foundation

// MARK: - Group Sync Status

public enum GroupSyncStatus: String, Codable {
    case pending
    case syncing
    case synced
    case failed
}

// MARK: - Group Type

public enum GroupType: String, Codable, CaseIterable {
    case standard
    case support
    case team
    case department
    case announcement
}

// MARK: - Routing Type

public enum RoutingType: String, Codable, CaseIterable {
    case manual
    case roundRobin
    case leastBusy
    case broadcast
}

// MARK: - Group Chat

public struct GroupChat: Identifiable, Equatable, Codable {
    // IDs
    let localId: String
    /// Backend id of the *conversation* this group is.
    var serverId: String?
    /// Backend id of the *group*, which the group endpoints key on.
    ///
    /// Separate from `serverId` because the two are separate ids on the wire, even
    /// though the backend currently sends the same value in both. Nil for groups
    /// stored before it was kept — read it through `resolvedGroupId`.
    var groupId: String?
    
    // Sync Status
    var isPendingCreation: Bool
    var isActive: Bool
    var syncStatus: GroupSyncStatus
    var syncError: String?
    var retryCount: Int
    
    // Basic Info
    var name: String
    var description: String?
    var avatarUrl: String?
    var icon: String?
    var color: String
    
    // Ownership
    var createdBy: String
//    var tenantId: String?
//    var communityId: String?
    
    // Group Type
//    var type: GroupType
//    var routingType: RoutingType?
    
    // Features
//    var isDefault: Bool
//    var isAnnouncementGroup: Bool
//    
    // Members
    var members: [GroupMember]
    
    // Settings
    var settings: GroupSettings
    
    // Counters
    var activeConversationCount: Int
//    
//    // Metadata
//    var metadata: [String: String]
    
    // Dates
    var createdAt: Date
    var updatedAt: Date
    
    // Computed
    public var id: String { serverId ?? localId }

    /// The id the group endpoints expect, or nil when this group has never synced.
    ///
    /// Falls back to `serverId` for groups stored before the group id was kept —
    /// which is the value every call site used anyway, so the fallback preserves
    /// their behaviour and the stored id takes over as it arrives.
    var resolvedGroupId: String? { groupId ?? serverId }
    var memberCount: Int { members.filter { $0.isActive }.count }
    var admins: [GroupMember] { members.filter { $0.role == .ADMIN } }
    var canOpenDiscussion: Bool { isActive && !isPendingCreation }

    /// Stable token used to remount dependent views when membership/admin state changes.
    var permissionsViewStateToken: String {
        let memberKey = members
            .map { "\($0.userId):\($0.role.rawValue):\($0.isActive)" }
            .joined(separator: "|")
        return "\(localId)|\(serverId ?? "")|\(createdBy)|\(memberKey)"
    }

    func isCurrentUserAdmin(currentUserId: String) -> Bool {
        guard !currentUserId.isEmpty else { return false }
        if createdBy == currentUserId { return true }
        return members.contains {
            $0.userId == currentUserId && $0.isActive && $0.role == .ADMIN
        }
    }

   public init(
        localId: String = UUID().uuidString.lowercased(),
        serverId: String? = nil,
        groupId: String? = nil,
        isPendingCreation: Bool = true,
        isActive: Bool = false,
        syncStatus: GroupSyncStatus = .pending,
        syncError: String? = nil,
        retryCount: Int = 0,
        name: String,
        description: String? = nil,
        avatarUrl: String? = nil,
        icon: String? = nil,
        color: String = "#3B82F6",
        createdBy: String,
//        tenantId: String? = nil,
//        communityId: String? = nil,
//        type: GroupType = .standard,
//        routingType: RoutingType? = nil,
//        isDefault: Bool = false,
//        isAnnouncementGroup: Bool = false,
        members: [GroupMember] = [],
        settings: GroupSettings = GroupSettings(),
        activeConversationCount: Int = 0,
//        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.localId = localId
        self.serverId = serverId
        self.groupId = groupId
        self.isPendingCreation = isPendingCreation
        self.isActive = isActive
        self.syncStatus = syncStatus
        self.syncError = syncError
        self.retryCount = retryCount
        self.name = name
        self.description = description
        self.avatarUrl = avatarUrl
        self.icon = icon
        self.color = color
        self.createdBy = createdBy
//        self.tenantId = tenantId
//        self.communityId = communityId
//        self.type = type
//        self.routingType = routingType
//        self.isDefault = isDefault
//        self.isAnnouncementGroup = isAnnouncementGroup
        self.members = members
        self.settings = settings
        self.activeConversationCount = activeConversationCount
//        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Group Member

public struct GroupMember: Identifiable, Equatable, Codable {
    public let id: String
    let userId: String
    var name: String
    var phone: String
    var avatar: String?
    var role: GroupRole
    
    // Permissions
    var canWrite: Bool
    
    // Status
    var isActive: Bool
    
    // Dates
    var joinedAt: Date
    var leftAt: Date?
    

  public init(
        userId: String,
        name: String,
        phone: String,
        avatar: String? = nil,
        role: GroupRole = .MEMBER,
        canWrite: Bool = true,
        isActive: Bool = true,
        joinedAt: Date = Date(),
        leftAt: Date? = nil,
    ) {
        self.id = userId
        self.userId = userId
        self.name = name
        self.phone = phone
        self.avatar = avatar
        self.role = role
        self.canWrite = canWrite
        self.isActive = isActive
        self.joinedAt = joinedAt
        self.leftAt = leftAt
    }
}

// MARK: - Group Role

public enum GroupRole: String, Codable, CaseIterable {
    case ADMIN
    case MEMBER

    var displayName: String {
        switch self {
        case .ADMIN:
            return "Admin"
        case .MEMBER:
            return "Member"
        }
    }
}

// MARK: - Group Settings
public struct GroupSettings: Codable, Equatable {
    
    // MARK: - Permissions
    
    public var onlyAdminsCanSend: Bool
    public var onlyAdminsCanEditInfo: Bool
    public var onlyAdminsCanAddMembers: Bool
    
    // MARK: - Approval
    
    public var approvalRequired: Bool
    
    // MARK: - Invite
    
    public var inviteLink: String?
    public var isInviteLinkActive: Bool
    public var inviteCode: String?
    public var inviteExpiresAt: Date?
    public var inviteRemainingUses: Int?
    
    // MARK: - Notifications
    
    public var muteNotifications: Bool
    
    // MARK: - Media
    
    public var allowMediaSharing: Bool

    /// When true, new members can see messages sent before they joined.
    public var sendMessagesHistory: Bool
    
    // MARK: - Initializer
    
    public init(
        onlyAdminsCanSend: Bool = false,
        onlyAdminsCanEditInfo: Bool = false,
        onlyAdminsCanAddMembers: Bool = false,
        approvalRequired: Bool = false,
        inviteLink: String? = nil,
        isInviteLinkActive: Bool = true,
        inviteCode: String? = nil,
        inviteExpiresAt: Date? = nil,
        inviteRemainingUses: Int? = nil,
        muteNotifications: Bool = false,
        allowMediaSharing: Bool = true,
        sendMessagesHistory: Bool = true
    ) {
        self.onlyAdminsCanSend = onlyAdminsCanSend
        self.onlyAdminsCanEditInfo = onlyAdminsCanEditInfo
        self.onlyAdminsCanAddMembers = onlyAdminsCanAddMembers
        self.approvalRequired = approvalRequired
        self.inviteLink = inviteLink
        self.isInviteLinkActive = isInviteLinkActive
        self.inviteCode = inviteCode
        self.inviteExpiresAt = inviteExpiresAt
        self.inviteRemainingUses = inviteRemainingUses
        self.muteNotifications = muteNotifications
        self.allowMediaSharing = allowMediaSharing
        self.sendMessagesHistory = sendMessagesHistory
    }

    enum CodingKeys: String, CodingKey {
        case onlyAdminsCanSend
        case onlyAdminsCanEditInfo
        case onlyAdminsCanAddMembers
        case approvalRequired
        case inviteLink
        case isInviteLinkActive
        case inviteCode
        case inviteExpiresAt
        case inviteRemainingUses
        case muteNotifications
        case allowMediaSharing
        case sendMessagesHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        onlyAdminsCanSend = try container.decodeIfPresent(Bool.self, forKey: .onlyAdminsCanSend) ?? false
        onlyAdminsCanEditInfo = try container.decodeIfPresent(Bool.self, forKey: .onlyAdminsCanEditInfo) ?? false
        onlyAdminsCanAddMembers = try container.decodeIfPresent(Bool.self, forKey: .onlyAdminsCanAddMembers) ?? false
        approvalRequired = try container.decodeIfPresent(Bool.self, forKey: .approvalRequired) ?? false
        inviteLink = try container.decodeIfPresent(String.self, forKey: .inviteLink)
        isInviteLinkActive = try container.decodeIfPresent(Bool.self, forKey: .isInviteLinkActive) ?? true
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode)
        inviteExpiresAt = try container.decodeIfPresent(Date.self, forKey: .inviteExpiresAt)
        inviteRemainingUses = try container.decodeIfPresent(Int.self, forKey: .inviteRemainingUses)
        muteNotifications = try container.decodeIfPresent(Bool.self, forKey: .muteNotifications) ?? false
        allowMediaSharing = try container.decodeIfPresent(Bool.self, forKey: .allowMediaSharing) ?? true
        sendMessagesHistory = try container.decodeIfPresent(Bool.self, forKey: .sendMessagesHistory) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(onlyAdminsCanSend, forKey: .onlyAdminsCanSend)
        try container.encode(onlyAdminsCanEditInfo, forKey: .onlyAdminsCanEditInfo)
        try container.encode(onlyAdminsCanAddMembers, forKey: .onlyAdminsCanAddMembers)
        try container.encode(approvalRequired, forKey: .approvalRequired)
        try container.encodeIfPresent(inviteLink, forKey: .inviteLink)
        try container.encode(isInviteLinkActive, forKey: .isInviteLinkActive)
        try container.encodeIfPresent(inviteCode, forKey: .inviteCode)
        try container.encodeIfPresent(inviteExpiresAt, forKey: .inviteExpiresAt)
        try container.encodeIfPresent(inviteRemainingUses, forKey: .inviteRemainingUses)
        try container.encode(muteNotifications, forKey: .muteNotifications)
        try container.encode(allowMediaSharing, forKey: .allowMediaSharing)
        try container.encode(sendMessagesHistory, forKey: .sendMessagesHistory)
    }
}

//// MARK: - Group Creation Request
//
//public struct CreateGroupRequest: Codable {
//    let name: String
//    let description: String?
//    let avatarData: Data?
//    let memberUserIds: [String]
//    let type: GroupType
//    let isAnnouncementGroup: Bool
//}

// MARK: - Group Notifications

extension Notification.Name {
    /// Un litige s'est ouvert ou fermé (MQTT) — les cartes de litige se relisent.
    static let financialDisputeChanged = Notification.Name("financialDisputeChanged")

    static let groupActivated = Notification.Name("groupActivated")
    static let groupSyncFailed = Notification.Name("groupSyncFailed")
    static let groupDeleted = Notification.Name("groupDeleted")
    static let groupSyncStatusChanged = Notification.Name("groupSyncStatusChanged")  // ✅ For real-time status updates
    static let discussionsShouldRefresh = Notification.Name("discussionsShouldRefresh")
    static let statusesShouldRefresh = Notification.Name("statusesShouldRefresh")
    /// Posted after a call-log sync wrote rows, so the Calls tab reloads.
    static let callLogsShouldRefresh = Notification.Name("callLogsShouldRefresh")
    /// Posted with `object` = codeStatus when a status image/poster is written to disk cache.
    static let statusMediaCached = Notification.Name("statusMediaCached")
    static let chatActionsDidChange = Notification.Name("chatActionsDidChange")
    /// Posted when a user requests to join a group — payload via `GroupJoinRequest.notificationUserInfo`
    static let groupJoinRequestReceived = Notification.Name("groupJoinRequestReceived")
    /// Posted when an outgoing message is persisted locally (before/without server ack).
    /// `object` is `OutgoingMessageLocallySavedEvent`.
    static let outgoingMessageLocallySaved = Notification.Name("outgoingMessageLocallySaved")
    /// Posted when a live location share this device owned stops — by the user,
    /// or by reaching its deadline. `object` is `LiveLocationShareEndedEvent`.
    ///
    /// The sender never receives their own `LIVE_LOCATION_STOP`, so this is the
    /// only way their own bubble learns the share is over.
    static let liveLocationShareEnded = Notification.Name("liveLocationShareEnded")
}

// MARK: - Group Errors

enum GroupError: Error {
    case notFound
    case alreadyExists
    case syncFailed(String)
    case invalidData
    case unauthorized
}
