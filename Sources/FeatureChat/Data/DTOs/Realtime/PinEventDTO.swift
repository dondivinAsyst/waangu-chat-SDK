// FeatureChat/Data/DTOs/PinEventDTO.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: OutboundPinEventDTO
// ─────────────────────────────────────────────────────────────
// Ce que le client ENVOIE quand il épingle ou désépingle un message.
// Topic : chat/{conversationId}/pins
//
// Le serveur vérifie les permissions via le JWT
// (admin/owner si onlyAdminsCanPinMessages = true).

public struct OutboundPinEventDTO: Codable, Sendable {

    // ── Identité ──────────────────────────────────────────────
    public let conversationId: String
    public let messageId:      String
    public let action:         String        // "pin" ou "unpin"
}

// ─────────────────────────────────────────────────────────────
// MARK: InboundPinEventDTO
// ─────────────────────────────────────────────────────────────
// Ce que le client REÇOIT quand un message est épinglé/désépinglé.
// Topic : chat/{conversationId}/pins
//
// Le serveur enrichit avec les détails du message épinglé
// et l'identité de celui qui a épinglé.

public struct InboundPinEventDTO: Codable, Sendable {

    // ── Identité ──────────────────────────────────────────────
    public let conversationId: String
    public let messageId:      String
    public let action:         String        // "pin" ou "unpin"
    public let timestamp:      Double

    // ── Qui a épinglé ─────────────────────────────────────────
    public let pinnedByUserId: String        // ← ajouté par le serveur (du JWT)
    public let pinnedByName:   String        // "Alice a épinglé un message"

    // ── Détails du message (pour la barre épinglée) ───────────
    // Présent uniquement pour action = "pin"
    // nil pour "unpin" — le client supprime le PinnedMessageModel
    public let messagePreview: String?       // "Salut !", "Photo", "Document"
    public let messageType:    String?       // "text", "image", "voice"...
    public let senderName:     String?       // qui a écrit le message original
}
