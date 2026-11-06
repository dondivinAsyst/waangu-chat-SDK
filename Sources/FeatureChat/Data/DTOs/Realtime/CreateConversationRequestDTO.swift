// FeatureChat/Data/DTOs/CreateConversationRequestDTO.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: CreateConversationRequestDTO
// ─────────────────────────────────────────────────────────────
// REST : POST /api/conversations
// Uniquement pour les GROUPES et CHANNELS.
// Les conversations directes sont créées automatiquement
// par le serveur au premier message MQTT.

public struct CreateConversationRequestDTO: Codable, Sendable {
    public let id:             String
    public let type:           String
    public let title:          String
    public let avatarURL:      String?
    public let participantIds: [String]
    public let firstMessage:   OutboundMessageDTO?
    public let settings:       GroupSettingsDTO?
}

// ─────────────────────────────────────────────────────────────
// MARK: CreateConversationResponseDTO
// ─────────────────────────────────────────────────────────────

public struct CreateConversationResponseDTO: Codable, Sendable {
    public let conversationId: String
    public let messageId:      String?          // nil si pas de firstMessage
    public let status:         String           // "created"
    public let timestamp:      Double
}



public struct GroupSettingsDTO: Codable, Sendable {
    public let description:                   String?
    public let onlyAdminsCanSendMessages:     Bool?
    public let onlyAdminsCanEditGroupInfo:    Bool?
    public let onlyAdminsCanAddMembers:       Bool?
    public let onlyAdminsCanPinMessages:      Bool?
    public let onlyAdminsCanCreatePolls:      Bool?
    public let requireAdminApproval:          Bool?
    public let disappearingMessagesSeconds:   Int?
    public let enforceDisappearingMessages:   Bool?    
    public let maxMembers:                    Int?
}


