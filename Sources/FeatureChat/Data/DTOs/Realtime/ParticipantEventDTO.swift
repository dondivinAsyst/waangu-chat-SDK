// FeatureChat/Data/DTOs/ParticipantEventDTO.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: OutboundParticipantEventDTO
// ─────────────────────────────────────────────────────────────
// Ce que le client ENVOIE quand il modifie les participants.
// Topic : chat/{conversationId}/participants
//
// Uniquement pour les groupes/channels.
// Le serveur vérifie les permissions (admin/owner) via le JWT.

public struct OutboundParticipantEventDTO: Codable, Sendable {
    public let conversationId: String
    public let action:         String        // "add", "remove", "promote", "demote", "leave"
    public let targetUserIds:  [String]      // qui est concerné
    public let role:           String?       // "admin", "member" — pour "promote"/"demote"
}

// ─────────────────────────────────────────────────────────────
// MARK: InboundParticipantEventDTO
// ─────────────────────────────────────────────────────────────
// Ce que le client REÇOIT quand les participants changent.
// Topic : chat/{conversationId}/participants

public struct InboundParticipantEventDTO: Codable, Sendable {
    public let conversationId:    String
    public let action:            String     // "add", "remove", "promote", "demote", "leave", "join"
    public let timestamp:         Double
    public let triggeredByUserId: String     // ← qui a déclenché (serveur)
    public let triggeredByName:   String
    public let participants:      [ParticipantDetailDTO]
}

// ─────────────────────────────────────────────────────────────
// MARK: ParticipantDetailDTO
// ─────────────────────────────────────────────────────────────

public struct ParticipantDetailDTO: Codable, Sendable {
    public let userId:    String
    public let phone:     String
    public let name:      String
    public let avatarURL: String?
    public let role:      String             // "owner", "admin", "member"
}
