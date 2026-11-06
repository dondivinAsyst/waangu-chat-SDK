//
//  GroupMapper.swift
//  FeatureChat
//
//  Adapted: GroupModel is gone.
//  A group is a ConversationModel with type == .group.
//  Members are ConversationParticipantModel.
//

import Foundation
import WaanguCoreKit

struct GroupMapper {

    // MARK: - GroupChat → ConversationModel

    /// `draft` and `isShowingDraft` are carried in from the row already on disk
    /// rather than derived from `GroupChat`, which knows nothing about the
    /// composer. A group save happens on every sync and every membership change;
    /// without this it would wipe whatever the user had half-typed.
    static func toConversation(
        _ group: GroupChat,
        draft: String? = nil,
        isShowingDraft: Bool? = nil
    ) -> ConversationModel {
        // Packed sync metadata lives in assignedAgentName; settings live in their
        // own GroupSettingsModel row; serverId has its own column.
        return ConversationModel(
            id: group.localId,
            serverId: group.serverId,
            // Written through as its own value, never derived from `serverId` —
            // persisting a fallback would make the two ids identical on disk and
            // erase the distinction the moment the backend needs it.
            groupId: group.groupId,
            type: .group,
            // An unnamed group stays unnamed rather than becoming named "".
            // `toDomain` reads a missing title as the empty string because
            // `GroupChat.name` is not optional, so writing it straight back turned
            // "no title yet" into a title of zero characters — which then defeats
            // the `title ?? "Group"` fallback the list falls back on, and the row
            // renders with a blank name.
            title: group.name.isEmpty ? nil : group.name,
            avatarURL: group.avatarUrl,
            lastMessageText: nil,
            lastMessageType: nil,
            lastMessageSenderName: nil,
            lastMessageAt: group.updatedAt,
            unreadCount: 0,
            isPinned: false,
            isArchived: false,   // archived is a user preference, not tied to group active state
            draft: draft,
            isShowingDraft: isShowingDraft,
            assignedAgentName: packSyncMetadata(
                syncStatus: group.syncStatus,
                isPending: group.isPendingCreation,
                retryCount: group.retryCount,
                createdBy: group.createdBy,
                color: group.color
            ),
            createdAt: group.createdAt,
            updatedAt: group.updatedAt
        )
    }

    // MARK: - ConversationModel + participants → GroupChat

    /// `settings` comes from the group's `GroupSettingsModel` row; a missing row
    /// yields defaults, which is what the previous `draft`-blob decoding did when
    /// it failed to parse.
    static func toDomain(
        _ conversation: ConversationModel,
        members: [GroupMember] = [],
        settings: GroupSettings = GroupSettings()
    ) -> GroupChat {
        let meta = (conversation.assignedAgentName ?? "").components(separatedBy: "|")
        let syncStatus   = GroupSyncStatus(rawValue: meta[safe: 0] ?? "") ?? .pending
        let isPending    = meta[safe: 1] == "1"
        let retryCount   = Int(meta[safe: 2] ?? "") ?? 0
        let serverId     = resolveServerId(from: conversation, meta: meta)
        let createdBy    = Self.createdBy(in: conversation.assignedAgentName)
        let color        = Self.color(in: conversation.assignedAgentName)

        return GroupChat(
            localId: conversation.id,
            serverId: serverId,
            groupId: conversation.groupId,
            isPendingCreation: isPending,
            isActive: !isPending && syncStatus == .synced,
            syncStatus: syncStatus,
            syncError: nil,
            retryCount: retryCount,
            name: conversation.title ?? "",
            description: nil,
            avatarUrl: conversation.avatarURL,
            icon: nil,
            color: color,
            createdBy: createdBy,
            members: members,
            settings: settings,
            activeConversationCount: 0,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt
        )
    }

    // MARK: - GroupMember → ConversationParticipantModel

    static func memberToParticipant(_ member: GroupMember, conversationId: String) -> ConversationParticipantModel {
        ConversationParticipantModel(
            id: "\(conversationId)_\(member.userId)".deterministicId,
            conversationId: conversationId,
            userId: member.userId,
            contactId: nil,
            phone: member.phone,
            role: mapRole(member.role),
            displayName: member.name,
            avatarURL: member.avatar,
            joinedAt: member.joinedAt,
            leftAt: member.leftAt,
            createdAt: member.joinedAt,
            updatedAt: Date()
        )
    }

    // MARK: - ConversationParticipantModel → GroupMember

    static func participantToMember(_ model: ConversationParticipantModel, fieldCrypto: any FieldEncryptionServiceProtocol) -> GroupMember {
        GroupMember(
            userId: model.userId,
            name: fieldCrypto.decrypt(model.displayName),
            phone: model.phone,
            avatar: model.avatarURL,
            role: mapGroupRole(model.role),
            canWrite: model.role != .member || model.leftAt == nil,
            isActive: model.isActive,
            joinedAt: model.joinedAt,
            leftAt: model.leftAt
        )
    }

    // MARK: - Role mapping

    private static func mapRole(_ role: GroupRole) -> ParticipantRoleModel {
        switch role {
        case .ADMIN:  return .admin
        case .MEMBER: return .member
        }
    }

    private static func mapGroupRole(_ role: ParticipantRoleModel) -> GroupRole {
        switch role {
        case .owner, .admin: return .ADMIN
        case .member:        return .MEMBER
        }
    }

    // MARK: - Sync metadata packing

    /// The metadata a group that arrived *from* the backend should carry.
    ///
    /// The discussion list only shows a group conversation whose packed status
    /// reads `synced` — that gate exists to hide groups this device is still
    /// creating. A group the server told us about is already synced by definition,
    /// so without this it is saved correctly and then filtered straight back out
    /// of the list.
    static func syncedMetadata(createdBy: String, color: String = "#3B82F6") -> String {
        packSyncMetadata(
            syncStatus: .synced,
            isPending: false,
            retryCount: 0,
            createdBy: createdBy,
            color: color
        )
    }

    /// The creator packed into a group conversation's metadata, or the empty string
    /// when it names none. Read rather than re-derived so a write that only means to
    /// change the sync status does not quietly drop who created the group.
    static func createdBy(in packed: String?) -> String {
        legacyCreatedBy(from: (packed ?? "").components(separatedBy: "|"))
    }

    /// The colour packed alongside it, so a metadata rewrite can carry it over.
    static func color(in packed: String?) -> String {
        legacyColor(from: (packed ?? "").components(separatedBy: "|"))
    }

    /// Whether packed metadata already marks the group as synced and settled.
    static func isSyncedMetadata(_ packed: String?) -> Bool {
        let meta = (packed ?? "").components(separatedBy: "|")
        let isPending = meta.count > 1 ? meta[1] == "1" : false
        return !isPending && meta.first == GroupSyncStatus.synced.rawValue
    }

    /// New format: syncStatus|isPending|retryCount|createdBy|color
    private static func packSyncMetadata(
        syncStatus: GroupSyncStatus,
        isPending: Bool,
        retryCount: Int,
        createdBy: String,
        color: String
    ) -> String {
        "\(syncStatus.rawValue)|\(isPending ? "1" : "0")|\(retryCount)|\(createdBy)|\(color)"
    }

    /// Prefer the dedicated column; fall back to legacy pipe index 3 when present.
    private static func resolveServerId(from conversation: ConversationModel, meta: [String]) -> String? {
        if let serverId = conversation.serverId {
            return serverId
        }
        // Legacy 6-part pipe: sync|pending|retry|serverId|createdBy|color
        if meta.count >= 6 {
            return meta[safe: 3].flatMap { $0.isEmpty ? nil : $0 }
        }
        return nil
    }

    private static func legacyCreatedBy(from meta: [String]) -> String {
        meta.count >= 6 ? (meta[safe: 4] ?? "") : (meta[safe: 3] ?? "")
    }

    private static func legacyColor(from meta: [String]) -> String {
        meta.count >= 6 ? (meta[safe: 5] ?? "#3B82F6") : (meta[safe: 4] ?? "#3B82F6")
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    /// Deterministic lowercase id string from any string (stable across calls).
    var deterministicId: String {
        let hash = abs(self.hashValue)
        return String(format: "%08x-0000-0000-0000-%012x", hash, hash)
    }
}
