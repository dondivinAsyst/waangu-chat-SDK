// FeatureChat/Data/DTOs/PresenceDTO.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: OutboundTypingDTO
// ─────────────────────────────────────────────────────────────
// Ce que le client ENVOIE quand il tape ou enregistre un vocal.
// Topic : waangu-chat/typing (topic de commande, plat)
//
// Fire-and-forget : jamais persisté en base.
// Le serveur broadcast aux autres participants.
// Timeout automatique côté serveur si pas de nouvel événement.

public enum TypingPayloadType: String, Codable, Sendable {
    case text = "TEXT"
    case audio = "AUDIO"
}

public struct OutboundTypingDTO: Codable, Sendable {
    public let senderId: String
    public let senderPhone: String
    public let conversationId: String
    public let type: TypingPayloadType

    public init(
        senderId: String,
        senderPhone: String,
        conversationId: String,
        type: TypingPayloadType
    ) {
        self.senderId = senderId
        self.senderPhone = senderPhone
        self.conversationId = conversationId
        self.type = type
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: InboundPresenceDTO
// ─────────────────────────────────────────────────────────────
// Ce que le client REÇOIT quand quelqu'un tape, enregistre, etc.
// Topic : waangu-chat/typing/{conversationId} — le backend relaie le payload
// publié par l'émetteur tel quel : ni userName ni timestamp ne sont ajoutés,
// et aucun événement d'arrêt n'est émis (l'entrée expire, cf. TypingStore).
//
// Le serveur enrichit avec userId, userName et timestamp.
// L'app stocke en mémoire (ContactPresenceState) — jamais en base.

public struct InboundPresenceDTO: Codable, Sendable {

    // ── Identité ──────────────────────────────────────────────
    public let conversationId: String
    public let userId:         String        // ← qui (ajouté par le serveur)
    public let userName:       String        // ← nom (ajouté par le serveur)
    public let event:          String        // "typing", "recordingVoice", "online", "offline", "idle"
    public let timestamp:      Double        // ← quand (epoch, ajouté par le serveur)
}
