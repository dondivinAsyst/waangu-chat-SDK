// FeatureChat/Data/DTOs/ConversationEventDTO.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: OutboundConversationEventDTO
// ─────────────────────────────────────────────────────────────
// Ce que le client ENVOIE quand il modifie une conversation.
// Topic : chat/{conversationId}/events
//
// Principalement pour les groupes :
//   "update" → changer nom, avatar, description
//   "delete" → supprimer la conversation
//   "clear"  → effacer les messages

public struct OutboundConversationEventDTO: Codable, Sendable {
    public let conversationId: String
    public let event:          String        // "update", "delete", "clear"
    public let title:          String?       // nil = pas changé
    public let avatarURL:      String?
    public let description:    String?
}

// ─────────────────────────────────────────────────────────────
// MARK: InboundConversationEventDTO
// ─────────────────────────────────────────────────────────────
// Ce que le client REÇOIT quand une conversation est créée,
// modifiée ou supprimée.
// Topics :
//   user/{userId}/conversations/new     → nouvelle conversation
//   user/{userId}/conversations/update  → modification
//   user/{userId}/conversations/delete  → suppression

public struct InboundConversationEventDTO: Codable, Sendable {
    public let conversationId:    String
    public let event:             String     // "new", "update", "delete", "clear"
    public let timestamp:         Double
    public let type:              String?    // "direct", "group", "channel"
    public let title:             String?
    public let avatarURL:         String?
    public let description:       String?
    public let participants:      [ConversationParticipantDTO]?
    public let triggeredByUserId: String?    // ← ajouté par le serveur
    public let triggeredByName:   String?
}

// ─────────────────────────────────────────────────────────────
// MARK: ConversationParticipantDTO
// ─────────────────────────────────────────────────────────────

public struct ConversationParticipantDTO: Codable, Sendable {
    public let userId: String
    public let phone:  String
    public let name:   String
    public let role:   String                // "owner", "admin", "member"
}
