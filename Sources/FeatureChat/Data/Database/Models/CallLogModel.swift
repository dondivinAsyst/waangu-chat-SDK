// FeatureChat/Data/Models/CallLogModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: CallLogModel
// ─────────────────────────────────────────────────────────────
// Historique complet des appels — onglet "Appels".
// Séparé de MessageModel car :
//   - L'onglet Appels affiche TOUS les appels
//   - MessageModel ne stocke que .missedCall dans le fil
//   - Les appels de groupe ont des participants
//
// Un appel manqué crée DEUX entrées :
//   1. CallLogModel dans l'onglet Appels
//   2. MessageModel(.missedCall) dans le fil de chat

public struct CallLogModel: Storable {
    public static let namespace        = "chat"
    public static let schemaVersion    = 1
    public static let indexedFields    = [
        "userId",
        "callType",
        "direction",
        "status",
        "calledAt",
        "isGroupCall",
    ]
    public static let searchableFields = ["contactName", "contactPhone"]
    public static let foreignKeys      = [
        StorableForeignKey("conversationId", references: "chat_conversationmodels", onDelete: .setNull)
    ]

    // ── Identité ──────────────────────────────────────────────
    public var id:             String
    public var userId:         String?         // nil pour les appels de groupe
    public var contactId:      String?
    public var conversationId: String?         // nil si pas de conversation

    // ── Dénormalisé (affichage sans jointure) ─────────────────
    public var contactName:      String
    public var contactPhone:     String
    public var contactAvatarURL: String?

    // ── Détails de l'appel ────────────────────────────────────
    public var callType:         CallMediaTypeModel
    public var direction:        CallDirectionModel
    public var status:           CallStatusModel
    public var durationSeconds:  Int
    public var calledAt:         Date
    public var endedAt:          Date?


    // ── Appel de groupe ───────────────────────────────────────
    public var isGroupCall:      Bool
    public var groupName:        String?
    public var participantCount: Int
    public var initiatedByUserId: String?      // qui a lancé l'appel
    public var participants:     [CallParticipantModel]?  // embarqué dans JSON

    // ── Sync ──────────────────────────────────────────────────
//    public var syncStatus:       SyncStatusModel

    // ── Métadonnées ───────────────────────────────────────────
    public var createdAt:        Date
    public var updatedAt:        Date

    // ── Init ──────────────────────────────────────────────────

    public init(
        id:                String             = UUID().uuidString.lowercased(),
        userId:            String?            = nil,
        contactId:         String?            = nil,
        conversationId:    String?            = nil,
        contactName:       String,
        contactPhone:      String,
        contactAvatarURL:  String?            = nil,
        callType:          CallMediaTypeModel,
        direction:         CallDirectionModel,
        status:            CallStatusModel    = .missed,
        durationSeconds:   Int                = 0,
        calledAt:          Date               = Date(),
        endedAt:           Date?              = nil,
        isGroupCall:       Bool               = false,
        groupName:         String?            = nil,
        participantCount:  Int                = 1,
        initiatedByUserId: String?            = nil,
        participants:      [CallParticipantModel]? = nil,
        syncStatus:        SyncStatusModel    = .pending,
        createdAt:         Date               = Date(),
        updatedAt:         Date               = Date()
    ) {
        self.id                = id
        self.userId            = userId
        self.contactId         = contactId
        self.conversationId    = conversationId
        self.contactName       = contactName
        self.contactPhone      = contactPhone
        self.contactAvatarURL  = contactAvatarURL
        self.callType          = callType
        self.direction         = direction
        self.status            = status
        self.durationSeconds   = durationSeconds
        self.calledAt          = calledAt
        self.endedAt           = endedAt
        self.isGroupCall       = isGroupCall
        self.groupName         = groupName
        self.participantCount  = participantCount
        self.initiatedByUserId = initiatedByUserId
        self.participants      = participants
        self.createdAt         = createdAt
        self.updatedAt         = updatedAt
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: CallParticipantModel (embarqué — pas une table)
// ─────────────────────────────────────────────────────────────

public struct CallParticipantModel: Codable, Sendable {
    public var userId: String
    public var name:   String
    /// Needed to place the call again from history. Optional so rows written
    /// before this field existed still decode.
    public var phone:  String?
    public var status: CallStatusModel

    public init(
        userId: String,
        name: String,
        phone: String? = nil,
        status: CallStatusModel = .answered
    ) {
        self.userId = userId
        self.name   = name
        self.phone  = phone
        self.status = status
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: CallMediaTypeModel
// ─────────────────────────────────────────────────────────────

public enum CallMediaTypeModel: String, Codable, Sendable {
    case voice
    case video
}

// ─────────────────────────────────────────────────────────────
// MARK: CallDirectionModel
// ─────────────────────────────────────────────────────────────

public enum CallDirectionModel: String, Codable, Sendable {
    case incoming
    case outgoing
}

// ─────────────────────────────────────────────────────────────
// MARK: CallStatusModel
// ─────────────────────────────────────────────────────────────

public enum CallStatusModel: String, Codable, Sendable {
    case answered
    case missed
    case declined
    case cancelled
    case noAnswer
    case busy
    /// The call never got off the ground — the server refused it. Rows written
    /// before this case existed recorded the same situation as `cancelled`.
    case failed
}
