//
//  ConversationSyncResponse.swift
//  FeatureChat
//
//  Conversation synchronization response DTOs
//  Endpoint: GET /api/v1/me/conversations/sync
//

import Foundation
import WaanguCoreKit

// MARK: - Main Response

public struct ConversationSyncResponseDTO: Codable {
    let success: Bool
    let data: ConversationSyncDataDTO?
    let nextCursor: String?
    let prevCursor: String?
    let hasMore: Bool?  // Made optional - may not be present in all responses
    let count: Int?
    let message: String?
    let timestamp: String?
}

// MARK: - Data Container

public struct ConversationSyncDataDTO: Codable {
    let serverTime: String
    let nextSinceCursor: String?
    let changedConversations: [ChangedConversationDTO]
}

// MARK: - Changed Conversation

public struct ChangedConversationDTO: Codable {
    let conversationId: String  // For GROUP: this IS the groupId
    /// "DIRECT", "GROUP", or "BROADCAST" (canal Updates) — mapped by
    /// `ConversationTypeMapper`. Only DIRECT carries `peer`.
    let conversationType: String
    let displayTitle: String?
    let displayAvatar: String?
    let peer: PeerInfoDTO?  // Only present for DIRECT conversations
    let lastActivityAt: String
    let messages: InboundMessageDTO?  // ✅ REUSE existing message DTO
    let userState: UserConversationStateDTO
    let changeType: String  // "CREATED" or "UPDATED"
}

extension ChangedConversationDTO {
    /// B58 — un aperçu de dernier message illisible ne fait pas échouer la page.
    ///
    /// L'aperçu (`messages`) n'est qu'un raccourci : les messages arrivent par
    /// la synchronisation propre à chaque conversation. Le 2026-10-12, un
    /// aperçu sans `senderId` faisait échouer le décodage de toute la réponse,
    /// donc la synchronisation de toutes les conversations, à chaque lancement.
    /// La conversation est gardée sans aperçu, et le cas est journalisé.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        conversationType = try container.decode(String.self, forKey: .conversationType)
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        displayAvatar = try container.decodeIfPresent(String.self, forKey: .displayAvatar)
        peer = try container.decodeIfPresent(PeerInfoDTO.self, forKey: .peer)
        lastActivityAt = try container.decode(String.self, forKey: .lastActivityAt)
        userState = try container.decode(UserConversationStateDTO.self, forKey: .userState)
        changeType = try container.decode(String.self, forKey: .changeType)
        do {
            messages = try container.decodeIfPresent(InboundMessageDTO.self, forKey: .messages)
        } catch {
            messages = nil
            debugLog("unreadable last-message preview for \(conversationId) — kept without preview (B58): \(error)",
                     category: "sync")
        }
    }
}

// MARK: - User Conversation State

public struct UserConversationStateDTO: Codable {
    let pinned: Bool?
    let archived: Bool?
    let muted: Bool?
    let muteUntil: String?
    let lastReadMessageId: String?
    let unreadCount: Int?
}

// MARK: - Peer Info (for DIRECT conversations)

public struct PeerInfoDTO: Codable {
    let userId: String
    let displayName: String
    let avatarUrl: String?
    let phone: String?  // ✅ Optional - API doesn't always send this
    let nickname: String?
    let role: String?  // ✅ Optional - defensive parsing
}


// MARK: - Message Sync Response (Phase 2)

public struct MessageSyncResponseDTO: Codable {
    let success: Bool
    let data: MessageSyncDataDTO?
    let timestamp: String?
}

public struct MessageSyncDataDTO: Codable {
    let items: [TimelineItemDTO]  // Timeline-based structure
    let count: Int?
}

// MARK: - Timeline Item

public struct TimelineItemDTO: Codable {
    let timelineId: String
    let type: String  // "MESSAGE", etc.
    let sortKey: Int64
    let occurredAt: String
    let itemKey: String
    let message: TimelineMessageDTO?  // The actual message data
}

// MARK: - Timeline Message (nested in timeline item)

public struct TimelineMessageDTO: Codable {
    let codeMessage: String  // Message ID
    let sortKey: Int?
    let senderId: String
    let senderName: String?
    let senderPhone: String?
    let senderAvatar: String?
    let content: String  // JSON string
    let typeMessage: String  // "TEXT", "IMAGE", etc.
    let status: String?  // "UNREAD", "READ", etc.
    let reply: String?
    let forwarded: Bool?
    let viewOnce: Bool?
    let isMoney: Bool?
    let transactionId: String?
    let isMessageSystem: Bool?
    let conversationSequence: Int?
    let forwardedMessageId: String?
    let encryptedContent: String?
    let encrypted: Bool?
    let sentAt: String
    let deleted: Bool?
    let pinned: Bool?
    let starred: Bool?
    let reported: Bool?
    let deliveries: [MessageDeliveryDTO]?
    let reads: [MessageReadDTO]?
    let reactions: [MessageReactionDTO]?
}

// MARK: - Supporting Message DTOs

public struct MessageDeliveryDTO: Codable {
    let userId: String?
    let deliveredAt: String?
}

public struct MessageReadDTO: Codable {
    let userId: String?
    let readAt: String?
}

public struct MessageReactionDTO: Codable {
    let userId: String?
    let reaction: String?
    let reactedAt: String?
}
