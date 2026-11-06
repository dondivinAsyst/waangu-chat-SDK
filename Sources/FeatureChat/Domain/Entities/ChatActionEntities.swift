//
//  ChatActionEntities.swift
//  FeatureChat
//
//  System action messages for chat events.
//  displayText(using:) uses TranslationKit for all user-visible strings.
//

import Foundation
import WaanguCoreKit

// MARK: - ChatActionType

public enum ChatActionType: String, Codable {
    case messageDeleted        = "MESSAGE_DELETED"
    case contactBlocked        = "CONTACT_BLOCKED"
    case contactUnblocked      = "CONTACT_UNBLOCKED"
    case messagesCleared       = "MESSAGES_CLEARED"
    case conversationArchived  = "CONVERSATION_ARCHIVED"
    case conversationUnarchived = "CONVERSATION_UNARCHIVED"
    case encryptionEnabled     = "ENCRYPTION_ENABLED"
    case groupCreated          = "GROUP_CREATED"
    /// Title, description, avatar or lock changed. The backend reports all four
    /// together without saying which moved, so the text stays deliberately vague.
    case groupUpdated          = "GROUP_UPDATED"
    case memberAdded           = "MEMBER_ADDED"
    /// Joined under their own steam — via an invite link or an approved request —
    /// rather than being added by someone. There is no actor but the joiner.
    case memberJoined          = "MEMBER_JOINED"
    case memberRemoved         = "MEMBER_REMOVED"
    case memberLeft            = "MEMBER_LEFT"
    case memberPromotedToAdmin = "MEMBER_PROMOTED_TO_ADMIN"
    case memberDemotedFromAdmin = "MEMBER_DEMOTED_FROM_ADMIN"
    case joinRequestReceived   = "JOIN_REQUEST_RECEIVED"
}

// MARK: - ChatActionItem

public struct ChatActionItem: Identifiable, Equatable, Codable {

    public let id: String
    public let conversationId: String
    public let actionType: ChatActionType
    public let performedBy: String
    public let targetId: String?
    public let metadata: [String: String]?
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        conversationId: String,
        actionType: ChatActionType,
        performedBy: String,
        targetId: String? = nil,
        metadata: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.actionType = actionType
        self.performedBy = performedBy
        self.targetId = targetId
        self.metadata = metadata
        self.timestamp = timestamp
    }

    // MARK: - Translated display text

    /// Returns the localised text for this event using the shared translator.
    /// Falls back to a plain English description if translator is not available.
    public func displayText(using translator: any TranslationServiceProtocol) -> String {
        let m = ChatTranslationKeys.MODULE
        let isYou = isCurrentUserActor

        switch actionType {

        case .messageDeleted:
            return translator.resolve(
                key: isYou ? ChatTranslationKeys.MESSAGE_DELETED_YOU : ChatTranslationKeys.MESSAGE_DELETED,
                module: m
            ).value

        case .contactBlocked:
            let name = metadata?["contactName"] ?? ""
            return translator.resolve(
                key: ChatTranslationKeys.CONTACT_BLOCKED_YOU,
                module: m,
                args: [name]
            ).value

        case .contactUnblocked:
            let name = metadata?["contactName"] ?? ""
            return translator.resolve(
                key: ChatTranslationKeys.CONTACT_UNBLOCKED_YOU,
                module: m,
                args: [name]
            ).value

        case .messagesCleared:
            return translator.resolve(
                key: isYou ? ChatTranslationKeys.MESSAGES_CLEARED_YOU : ChatTranslationKeys.MESSAGES_CLEARED,
                module: m
            ).value

        case .conversationArchived:
            return translator.resolve(key: ChatTranslationKeys.CONVERSATION_ARCHIVED, module: m).value

        case .conversationUnarchived:
            return translator.resolve(key: ChatTranslationKeys.CONVERSATION_UNARCHIVED, module: m).value

        case .encryptionEnabled:
            return translator.resolve(key: ChatTranslationKeys.ENCRYPTION_ENABLED, module: m).value

        case .groupCreated:
            if isYou {
                return translator.resolve(key: ChatTranslationKeys.GROUP_CREATED_YOU, module: m).value
            }
            return translator.resolve(
                key: ChatTranslationKeys.GROUP_CREATED_ACTOR,
                module: m,
                args: [actorDisplayName]
            ).value

        case .groupUpdated:
            if isYou {
                return translator.resolve(key: ChatTranslationKeys.GROUP_UPDATED_YOU, module: m).value
            }
            return translator.resolve(
                key: ChatTranslationKeys.GROUP_UPDATED_ACTOR,
                module: m,
                args: [actorDisplayName]
            ).value

        case .memberAdded:
            let memberName = metadata?["memberName"] ?? ""
            if isYou {
                return translator.resolve(
                    key: ChatTranslationKeys.USER_ADDED_YOU_ACTOR,
                    module: m,
                    args: [memberName]
                ).value
            }
            // Check if current user is the target
            if isCurrentUserTarget {
                return translator.resolve(
                    key: ChatTranslationKeys.USER_ADDED_YOU_TARGET,
                    module: m,
                    args: [actorDisplayName]
                ).value
            }
            return translator.resolve(
                key: ChatTranslationKeys.USER_ADDED_ACTOR,
                module: m,
                args: [actorDisplayName, memberName]
            ).value

        case .memberRemoved:
            let memberName = metadata?["memberName"] ?? ""
            if isYou {
                return translator.resolve(
                    key: ChatTranslationKeys.USER_REMOVED_YOU_ACTOR,
                    module: m,
                    args: [memberName]
                ).value
            }
            if isCurrentUserTarget {
                return translator.resolve(
                    key: ChatTranslationKeys.USER_REMOVED_YOU_TARGET,
                    module: m,
                    args: [actorDisplayName]
                ).value
            }
            return translator.resolve(
                key: ChatTranslationKeys.USER_REMOVED_ACTOR,
                module: m,
                args: [actorDisplayName, memberName]
            ).value

        case .memberJoined:
            if isYou {
                return translator.resolve(key: ChatTranslationKeys.USER_JOINED_YOU, module: m).value
            }
            let memberName = metadata?["memberName"] ?? actorDisplayName
            return translator.resolve(
                key: ChatTranslationKeys.USER_JOINED,
                module: m,
                args: [memberName]
            ).value

        case .memberLeft:
            if isYou {
                return translator.resolve(key: ChatTranslationKeys.USER_LEFT_YOU, module: m).value
            }
            let memberName = metadata?["memberName"] ?? actorDisplayName
            return translator.resolve(
                key: ChatTranslationKeys.USER_LEFT,
                module: m,
                args: [memberName]
            ).value

        case .memberPromotedToAdmin:
            let memberName = metadata?["memberName"] ?? ""
            if isYou {
                return translator.resolve(
                    key: ChatTranslationKeys.ADD_ADMIN_YOU_ACTOR,
                    module: m,
                    args: [memberName]
                ).value
            }
            if isCurrentUserTarget {
                return translator.resolve(
                    key: ChatTranslationKeys.ADD_ADMIN_YOU_TARGET,
                    module: m,
                    args: [actorDisplayName]
                ).value
            }
            return translator.resolve(
                key: ChatTranslationKeys.ADD_ADMIN_ACTOR,
                module: m,
                args: [actorDisplayName, memberName]
            ).value

        case .memberDemotedFromAdmin:
            let memberName = metadata?["memberName"] ?? ""
            if isYou {
                return translator.resolve(
                    key: ChatTranslationKeys.REMOVE_ADMIN_YOU_ACTOR,
                    module: m,
                    args: [memberName]
                ).value
            }
            if isCurrentUserTarget {
                return translator.resolve(
                    key: ChatTranslationKeys.REMOVE_ADMIN_YOU_TARGET,
                    module: m,
                    args: [actorDisplayName]
                ).value
            }
            return translator.resolve(
                key: ChatTranslationKeys.REMOVE_ADMIN_ACTOR,
                module: m,
                args: [actorDisplayName, memberName]
            ).value

        case .joinRequestReceived:
            let requesterName = metadata?["requesterName"] ?? actorDisplayName
            return translator.resolve(
                key: ChatTranslationKeys.JOIN_REQUEST_RECEIVED,
                module: m,
                args: [requesterName]
            ).value
        }
    }

    public var isJoinRequestCheckpoint: Bool {
        actionType == .joinRequestReceived
    }

    // MARK: - Icon

    public var iconName: String {
        switch actionType {
        case .messageDeleted:          return "trash"
        case .contactBlocked:          return "hand.raised.fill"
        case .contactUnblocked:        return "hand.raised.slash"
        case .messagesCleared:         return "trash.circle"
        case .conversationArchived:    return "archivebox"
        case .conversationUnarchived:  return "tray.and.arrow.up"
        case .encryptionEnabled:       return "lock.shield"
        case .groupCreated:            return "person.3.fill"
        case .groupUpdated:            return "pencil.circle"
        case .memberAdded:             return "person.badge.plus"
        case .memberJoined:            return "person.crop.circle.badge.checkmark"
        case .memberRemoved:           return "person.badge.minus"
        case .memberLeft:              return "rectangle.portrait.and.arrow.right"
        case .memberPromotedToAdmin:   return "person.badge.key.fill"
        case .memberDemotedFromAdmin:  return "person.badge.minus"
        case .joinRequestReceived:     return "person.badge.clock"
        }
    }

    // MARK: - Private helpers

    /// Two unknowns are not the same person.
    ///
    /// `currentUid` is the empty string until `AppSettings` is injected, and an
    /// event whose actor could not be resolved carries an empty `performedBy` —
    /// compared directly, those two make every such event read as "You".
    private var isCurrentUserActor: Bool {
        let currentUserId = CurrentSessionInfo.shared.currentUid
        guard !currentUserId.isEmpty, !performedBy.isEmpty else { return false }
        return performedBy == currentUserId
    }

    private var isCurrentUserTarget: Bool {
        let currentUserId = CurrentSessionInfo.shared.currentUid
        guard let targetId, !targetId.isEmpty, !currentUserId.isEmpty else { return false }
        return targetId == currentUserId
    }

    private var actorDisplayName: String {
        metadata?["performedByName"] ?? ""
    }
}

// MARK: - Group system messages

public extension ChatActionItem {

    /// The checkpoint a group system message renders as.
    ///
    /// Group events arrive as messages — the backend projects them into the thread
    /// — but they display as checkpoints, so this is where one becomes the other.
    /// Returns nil for anything that is not a group event.
    ///
    /// The message id carries over as the action id: it is what makes a redelivered
    /// event replace the row it already wrote instead of adding a second bubble.
    init?(groupEvent message: MessageDataItem, conversationId: String, groupName: String? = nil) {
        guard let actionType = ChatActionType(groupEvent: message.typeMessage) else {
            return nil
        }

        let event = message.message.groupEvent
        var metadata: [String: String] = [:]
        if !message.senderName.isEmpty {
            metadata["performedByName"] = message.senderName
        }
        if let targetName = event?.targetName, !targetName.isEmpty {
            metadata["memberName"] = targetName
        }
        if let name = event?.groupTitle ?? groupName, !name.isEmpty {
            metadata["groupName"] = name
        }

        self.init(
            id: message.codeMessage,
            conversationId: conversationId,
            actionType: actionType,
            performedBy: message.senderId,
            targetId: event?.targetUserId,
            metadata: metadata.isEmpty ? nil : metadata,
            timestamp: message.createdAt
        )
    }
}

public extension ChatActionType {

    /// The action a group message type describes, or nil if it describes none.
    init?(groupEvent type: MessageTypeProps) {
        switch type {
        case .GROUP_CREATED:            self = .groupCreated
        case .GROUP_UPDATED:            self = .groupUpdated
        case .USER_ADDED_TO_GROUP:      self = .memberAdded
        case .USER_JOINED_GROUP:        self = .memberJoined
        case .USER_LEFT_GROUP:          self = .memberLeft
        case .USER_REMOVED_FROM_GROUP:  self = .memberRemoved
        case .USER_PROMOTED_TO_ADMIN:   self = .memberPromotedToAdmin
        case .USER_DEMOTED_FROM_ADMIN:  self = .memberDemotedFromAdmin
        default:                        return nil
        }
    }
}
