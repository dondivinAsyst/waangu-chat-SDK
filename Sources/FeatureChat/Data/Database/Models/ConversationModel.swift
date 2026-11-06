// FeatureChat/Data/Models/ConversationModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: ConversationModel
// ─────────────────────────────────────────────────────────────
// Données métier de la conversation.
// Les préférences (mute, wallpaper, lock...) sont dans ChatPreferenceModel.
// Les permissions groupe sont dans GroupSettingsModel.
//
// Créée uniquement quand :
//   - L'utilisateur envoie le premier message (offline OK)
//   - Un message est reçu d'un autre utilisateur
// Jamais créée à l'ouverture de l'écran chat vierge.

public struct ConversationModel: Storable {
    public static let namespace        = "chat"
    /// Keep in sync with `ChatDatabaseRegistration` ConversationModel FieldMigrations (latest → 2).
    public static let schemaVersion    = 2
    public static let indexedFields    = [
        "type",
        "serverId",
        "isPinned",
        "isArchived",
        "isStarted",
        "status",
        "lastMessageAt",
        "unreadCount",
        "syncStatus",
    ]
    public static let searchableFields = ["title", "lastMessageText"]
    public static let foreignKeys: [StorableForeignKey] = []

    // ── Identité ──────────────────────────────────────────────
    public var id:        String
    /// Backend conversation id when synced; nil until the server assigns one.
    public var serverId:  String?
    /// Backend group id, for group conversations.
    ///
    /// Kept as its own field rather than assumed equal to `serverId`: the group
    /// endpoints take a group id, and outbound messages carry one alongside the
    /// conversation id. The backend currently sends the same value in both, but
    /// nothing on the wire promises that, and inferring it would send the
    /// conversation id to every group endpoint the day they diverge.
    ///
    /// Nil for direct conversations, and for group rows written before this
    /// existed — read it through `resolvedGroupId`.
    public var groupId:   String?
    public var type:      ConversationTypeModel
    public var title:     String?
    public var avatarURL: String?

    // ── Dernier message (dénormalisé pour la liste) ───────────
    public var lastMessageText:       String?
    public var lastMessageType:       MessageTypeModel?
    public var lastMessageSenderName: String?
    public var lastMessageAt:        Date?

    // ── État utilisateur ──────────────────────────────────────
    public var unreadCount: Int
    public var isPinned:    Bool
    public var pinnedAt: Date?
    public var isArchived:  Bool
    /// Text left in the composer when the user backed out of the chat room.
    /// Nil once sent or cleared. The chat list shows it in place of the last
    /// message.
    public var draft:       String?
    /// Whether the list should render `draft` instead of the last message.
    /// Stored rather than derived so a draft can be kept without being shown.
    public var isShowingDraft: Bool?

    /// Set when this row was folded into another conversation with the same
    /// peer, and holds that conversation's local id.
    ///
    /// The row itself is kept rather than deleted, because a conversation the
    /// server still lists is recreated by the next sync — a deleted duplicate
    /// would simply come back, and the merge would undo itself on every launch.
    /// Kept as an alias instead: the inbox skips it, and everything addressed
    /// to it is redirected to the conversation it points at.
    ///
    /// Deliberately not in `indexedFields`: the schema gives real columns only
    /// to indexed fields and foreign keys and puts the rest in `json_payload`,
    /// so an optional field added here needs no migration and reads back as nil
    /// on every row written before it existed.
    public var mergedIntoId: String?

    // ── Métadonnées ───────────────────────────────────────────
    public var assignedAgentName:  String?
    public var lastReadMessageId:  String?
//    public var syncStatus:         SyncStatusModel
    public var createdAt:          Date
    public var updatedAt:          Date

    /// Backend id when available; otherwise the local UUID string.
    public var resolvedServerId: String {
        serverId ?? id
    }

    /// The id the group endpoints expect.
    ///
    /// Falls back to the conversation id for rows written before `groupId` was
    /// stored — which is what every call site assumed anyway, so the fallback
    /// changes nothing for them and the stored value takes over as it arrives.
    public var resolvedGroupId: String {
        groupId ?? resolvedServerId
    }

    // ── Init ──────────────────────────────────────────────────

    public init(
        id:                    String                  = UUID().uuidString.lowercased(),
        serverId:              String?                 = nil,
        groupId:               String?                 = nil,
        type:                  ConversationTypeModel,
        title:                 String?                 = nil,
        avatarURL:             String?                 = nil,
        lastMessageText:       String?                 = nil,
        lastMessageType:       MessageTypeModel?       = nil,
        lastMessageSenderName: String?                 = nil,
        lastMessageAt:         Date?                   = nil,
        unreadCount:           Int                     = 0,
        isPinned:              Bool                    = false,
        isArchived:            Bool                    = false,
        draft:                 String?                 = nil,
        isShowingDraft:        Bool?                   = false,
        mergedIntoId:          String?                 = nil,
        assignedAgentName:     String?                 = nil,
        lastReadMessageId:     String?                 = nil,
//        syncStatus:            SyncStatusModel         = .pending,
        createdAt:             Date                    = Date(),
        updatedAt:             Date                    = Date()
    ) {
        self.id                    = id
        self.serverId              = serverId
        self.groupId               = groupId
        self.type                  = type
        self.title                 = title
        self.avatarURL             = avatarURL
        self.lastMessageText       = lastMessageText
        self.lastMessageType       = lastMessageType
        self.lastMessageSenderName = lastMessageSenderName
        self.lastMessageAt         = lastMessageAt
        self.unreadCount           = unreadCount
        self.isPinned              = isPinned
        self.isArchived            = isArchived
        self.draft                 = draft
        self.isShowingDraft        = isShowingDraft
        self.mergedIntoId          = mergedIntoId
        self.assignedAgentName     = assignedAgentName
        self.lastReadMessageId     = lastReadMessageId
//        self.syncStatus            = syncStatus
        self.createdAt             = createdAt
        self.updatedAt             = updatedAt
    }
}
