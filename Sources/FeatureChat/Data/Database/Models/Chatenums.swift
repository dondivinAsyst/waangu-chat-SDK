// FeatureChat/Data/Models/ChatEnums.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: ConversationTypeModel
// ─────────────────────────────────────────────────────────────

public enum ConversationTypeModel: String, Codable, Sendable {
    case direct
    case group
    case support
    case channel
    case selfChat
    /// La conversation avec Waangu Copilot — **sur l'appareil seulement**.
    ///
    /// Aucun serveur ne la connaît : elle n'est ni synchronisée, ni fusionnée,
    /// ni publiée, et son identifiant ne part jamais vers Chat Core. Ses
    /// messages vivent dans `CopilotMessageModel`, pas dans la table des messages.
    case copilot
}

public extension ConversationTypeModel {
    /// Conversations addressed to a room rather than to one person.
    ///
    /// There is no peer participant to resolve for these: the title and the
    /// avatar come from the conversation row itself. A broadcast channel is one
    /// of them — it arrives with no `peer`, exactly like a group.
    var isMultiParty: Bool {
        self == .group || self == .channel
    }

    /// Conversations qui portent un correspondant à résoudre.
    ///
    /// Distinct de ``isMultiParty`` : le dossier personnel (`selfChat`) n'est
    /// pas une salle — rien n'y est diffusé, il n'a pas d'identifiant de
    /// groupe — mais il n'a pas non plus d'interlocuteur. Son titre vient de la
    /// ligne de conversation, comme celui d'un groupe. Confondre les deux
    /// notions faisait chercher un correspondant qui n'existe pas.
    var hasPeer: Bool { self == .direct }
}



// ─────────────────────────────────────────────────────────────
// MARK: MessageTypeModel
// ─────────────────────────────────────────────────────────────

public enum MessageTypeModel: String, Codable, Sendable {

    // Contenu standard
    case text
    case image
    case video
    case videoNote
    case voice
    case audio
    case document
    case sticker
    case gif

    // Contenu riche
    case location
    case liveLocation
    case contact
    case poll

    // Waangu-specific
    case payment
    case rideUpdate
    case orderUpdate

    // Système
    case system
    case missedCall
    case encrypted
    case deleted
    // for stories
    case status

    /// A record written into a thread rather than something a user sent.
    ///
    /// The storage-level counterpart of `MessageTypeProps.isCallEvent`, widened
    /// to the rest of the system records because this enum is coarser: both
    /// connected-call types and `GROUP_CREATED` collapse to `system`, and both
    /// missed-call types to `missedCall`. None of them were transmitted, so none
    /// can be acknowledged with a read receipt — the id on the row is a call or
    /// system id the server cannot resolve to a message.
    public var isSystemEvent: Bool {
        switch self {
        case .system, .missedCall:
            return true
        default:
            return false
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: MessageDeliveryStatusModel
// ─────────────────────────────────────────────────────────────

public enum MessageDeliveryStatusModel: String, Codable, Sendable {
    case pending      // ⏳ pas encore envoyé
    case sent         // ✓  serveur a reçu
    case delivered    // ✓✓ gris
    case read         // ✓✓ bleu
    case failed       // ❌ échec
}

// ─────────────────────────────────────────────────────────────
// MARK: SyncStatusModel
// ─────────────────────────────────────────────────────────────

public enum SyncStatusModel: String, Codable, Sendable {
    case pending      // créé localement, pas encore sync
    case syncing      // en cours d'envoi
    case synced       // confirmé par le serveur
    case failed       // échec — à réessayer
}

// ─────────────────────────────────────────────────────────────
// MARK: PreferenceTargetTypeModel
// ─────────────────────────────────────────────────────────────

public enum PreferenceTargetTypeModel: String, Codable, Sendable {
    case direct        // targetKey = numéro de téléphone ("+257...")
    case conversation  // targetKey = opaque conversationId string
}

// ─────────────────────────────────────────────────────────────
// MARK: ChatFontSizeModel
// ─────────────────────────────────────────────────────────────

public enum ChatFontSizeModel: String, Codable, Sendable {
    case small
    case medium
    case large
}

// ─────────────────────────────────────────────────────────────
// MARK: CallTypeModel
// ─────────────────────────────────────────────────────────────

public enum CallTypeModel: String, Codable, Sendable {
    case voiceIncoming
    case voiceOutgoing
    case videoIncoming
    case videoOutgoing
}

// ─────────────────────────────────────────────────────────────
// MARK: ContactPresenceModel
// ─────────────────────────────────────────────────────────────
// Fire-and-forget — jamais persisté en base.
// Utilisé uniquement en mémoire via RealtimeKit.

public enum ContactPresenceModel: String, Codable, Sendable {
    case online
    case offline
    case typing
    case recordingVoice
    case recordingVideo
    case uploadingPhoto
    case uploadingFile
}

// ─────────────────────────────────────────────────────────────
// MARK: ContactPresenceState (mémoire uniquement)
// ─────────────────────────────────────────────────────────────

public struct ContactPresenceState: Sendable {
    public let contactId: String
    public let status:    ContactPresenceModel
    public let timestamp: Date

    public init(contactId: String, status: ContactPresenceModel, timestamp: Date = Date()) {
        self.contactId = contactId
        self.status    = status
        self.timestamp = timestamp
    }
}
