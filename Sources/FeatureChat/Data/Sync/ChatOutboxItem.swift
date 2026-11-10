// MARK: - FeatureChat/Data/Sync/ChatOutboxItem.swift
//
// Module  : FeatureChat
// Rôle    : Item d'outbox spécifique au chat.
//           Les factory methods utilisent les Outbound*DTO existants.

import Foundation
import WaanguCoreKit

// MARK: - ChatOutboxItemActionType

/// Types d'actions disponibles pour l'outbox du chat
public enum ChatOutboxItemActionType: String, Codable, Sendable {
    // Messages
    case sendMessage = "send_message"
    case modifyMessage = "modify_message"
    case deleteMessage = "delete_message"
    
    // Réactions
    case reaction = "reaction"

    // Sondages
    case pollVote = "poll_vote"

    // Accusés de réception/lecture
    case deliveryReceipt = "delivery_receipt"
    case readReceipt = "read_receipt"
    
    // Participants
    case participantEvent = "participant_event"
    
    // Conversations
    case conversationEvent = "conversation_event"
    
    // Stories (sans conversation)
    case statusEvent = "status_event"
    case viewStory = "view_story"
    case deleteStory = "delete_story"
    case reactStory = "react_story"
}

// MARK: - ChatOutboxItem

public struct ChatOutboxItem: OutboxItemProtocol, Storable {
    public typealias ActionType = ChatOutboxItemActionType
    
    public static let namespace = "chat"
    public static let schemaVersion = 1
    
    public static let indexedFields    = ["syncStatus", "idempotencyKey"]
    
    public var id: String
    public var actionType: ChatOutboxItemActionType
    public var payload: Data
    public var idempotencyKey: String
    public var createdAt: Date
    public var syncStatus: OutboxSyncStatus
    public var retryCount: Int
    public var lastError: String?
    public var conversationId: String
    
    public init(
        id: String = UUID().uuidString.lowercased(),
        actionType: ChatOutboxItemActionType,
        payload: Data,
        idempotencyKey: String,
        conversationId: String,
        createdAt: Date = Date(),
        syncStatus: OutboxSyncStatus = .pending,
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.actionType = actionType
        self.payload = payload
        self.idempotencyKey = idempotencyKey
        self.conversationId = conversationId
        self.createdAt = createdAt
        self.syncStatus = syncStatus
        self.retryCount = retryCount
        self.lastError = lastError
    }
}

// MARK: - Factory Helpers

extension ChatOutboxItem {
    
    // ── Messages ──────────────────────────────────────────────
    
    public static func sendMessage(_ dto: OutboundMessageDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.sendMessage
        return ChatOutboxItem(
            actionType: actionType,
            // The nonce belongs to one send attempt, not to the message: never stored.
            payload: (try? dto.withoutNonce().toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.codeMessage)",
            conversationId: dto.conversationId
        )
    }
    
    public static func modifyMessage(_ dto: OutboundModifyMessageDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.modifyMessage
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.codeMessage)",
            conversationId: dto.conversationId
        )
    }
    
    public static func deleteMessage(_ dto: OutboundMessageDeleteDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.deleteMessage
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.codeMessage):\(dto.forEveryone)",
            conversationId: dto.conversationId
        )
    }
    
    // ── Reactions ─────────────────────────────────────────────
    
    public static func reactMessage(_ dto: OutboundReactMessageDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.reaction
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.codeMessage):\(dto.reaction):add",
            conversationId: dto.conversationId
        )
    }

    public static func removeReaction(_ dto: OutboundRemoveReactionDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.reaction
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.codeMessage):\(dto.userId):remove",
            conversationId: dto.conversationId
        )
    }

    public static func reaction(_ dto: OutboundReactionDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.reaction
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.messageId):\(dto.emoji):\(dto.action)",
            conversationId: dto.conversationId
        )
    }
    
    // ── Sondages ──────────────────────────────────────────────

    public static func votePoll(_ dto: OutboundVotePollDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.pollVote
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            // One selection per user per poll: changing your mind while offline
            // replaces the queued vote rather than queueing behind it, so the
            // server only ever sees the answer that was actually settled on.
            idempotencyKey: "\(actionType.rawValue):\(dto.codeMessage):\(dto.userId)",
            conversationId: dto.conversationId
        )
    }

    // ── Delivery Receipts ─────────────────────────────────────
    
    public static func markDelivered(_ dto: OutboundMarkDeliveredDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.deliveryReceipt
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.codeMessage)",
            conversationId: dto.conversationId
        )
    }

    public static func markAsRead(
        _ dto: OutboundMarkAsReadDTO,
        conversationId: String
    ) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.readReceipt
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.codeMessage)",
            conversationId: conversationId
        )
    }
    
    // ── Participants ──────────────────────────────────────────
    
    public static func participantEvent(_ dto: OutboundParticipantEventDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.participantEvent
        let targetIds = dto.targetUserIds.joined(separator: ",")
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.conversationId):\(dto.action):\(targetIds)",
            conversationId: dto.conversationId
        )
    }
    
    // ── Conversation Events ───────────────────────────────────
    
    public static func conversationEvent(_ dto: OutboundConversationEventDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.conversationEvent
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.conversationId):\(dto.event)",
            conversationId: dto.conversationId
        )
    }
    
    // ── Story Events (sans conversation) ──────────────────────

    public static func viewStory(_ dto: OutboundViewStoryDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.viewStory
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.storyId):\(dto.viewerId)",
            conversationId: ""
        )
    }

    public static func deleteStory(_ dto: OutboundDeleteStoryDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.deleteStory
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.storyId)",
            conversationId: ""
        )
    }

    public static func reactStory(_ dto: OutboundReactStoryDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.reactStory
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.storyId):\(dto.userId):\(dto.reaction)",
            conversationId: ""
        )
    }

    /// Legacy — prefer `viewStory` / `deleteStory` / `reactStory`.
    public static func statusEvent(_ dto: OutboundStatusEventDTO) -> ChatOutboxItem {
        let actionType = ChatOutboxItemActionType.statusEvent
        return ChatOutboxItem(
            actionType: actionType,
            payload: (try? dto.toJSONData()) ?? Data(),
            idempotencyKey: "\(actionType.rawValue):\(dto.statusId):\(dto.event)",
            conversationId: ""
        )
    }
}

// MARK: - Convenience Extensions

extension ChatOutboxItem {
    /// Vérifie si l'action est liée à une conversation
    public var requiresConversation: Bool {
        switch actionType {
        case .statusEvent, .viewStory, .deleteStory, .reactStory:
            return false
        default:
            return true
        }
    }
    
    /// Retourne l'actionType sous forme de String pour le protocole
    public var actionTypeString: String {
        actionType.rawValue
    }
}
