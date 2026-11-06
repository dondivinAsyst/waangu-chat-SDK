// FeatureChat/Data/Models/MessageModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: MessageModel
// ─────────────────────────────────────────────────────────────

public struct MessageModel: Storable {
    public static let namespace        = "chat"
    public static let schemaVersion    = 1
    public static let indexedFields    = [
        "conversationId",
        "senderId",
        "timestamp",
        "type",
        "deliveryStatus",
        "isDeleted",
        "syncStatus",
        // Kept as a column only so a re-save writes NULL over the old plaintext.
        "searchText",
    ]
    public static let searchableFields = [String]()
    public static let foreignKeys      = [
        StorableForeignKey(
            "conversationId",
            references: "chat_conversationmodels",
            onDelete: .cascade
        )
    ]

    // ── Identité ──────────────────────────────────────────────
    /// Local/backend message id (`codeMessage`). Stored as String — never rewrite via UUID.uuidString.
    public var id:             String
    public var conversationId: String
    /// Backend group id for messages in a group.
    ///
    /// Outbound messages carry a group id alongside the conversation id, so a
    /// message rebuilt from storage for sending needs its own copy — deriving it
    /// from `conversationId` would put the wrong id on the wire the day the
    /// backend stops making them equal. Nil for direct chats and for rows written
    /// before this existed.
    public var groupId:        String?
    /// Backend user ID stored as String to support non-UUID formats (e.g. MongoDB ObjectId).
    public var senderId:       String
    public var senderName:     String
    public var senderPhone:     String
    
    // reciever
    public var receiverId:     String
    

    // ── Contenu ───────────────────────────────────────────────
    public var type:       MessageTypeModel
    public var content:    MessageContentModel
    /// Plaintext copy once kept for FTS5 (F-13). Never written any more; only decoded
    /// from rows saved before, and cleared by `ChatFeature.scrubLegacyPlaintext`.
    public var searchText: String?
    public var timestamp:  Date

    // ── Livraison (✓ ✓✓) ──────────────────────────────────────
    public var deliveryStatus: MessageDeliveryStatusModel

    // ── Réponse (swipe-to-reply) ────────────────────────────── an object
    public var replyToMessageId:      String?
    public var replyToSenderName:     String?
    public var replyToMessageType:    MessageTypeModel?
    public var replyToMessagePreview: String?
    public var replyToThumbnailURL:   String?
    /// Le message cité a été supprimé pour tous : la copie ci-dessus est vidée
    /// et la citation affiche « supprimé » (B44). Optionnel pour décoder les
    /// lignes écrites avant ce champ — `nil` vaut `false`.
    public var replyToIsDeleted:      Bool?

    // ── Transfert ─────────────────────────────────────────────
    public var isForwarded:  Bool
    public var forwardCount: Int

    // ── Édition ───────────────────────────────────────────────
    public var isEdited: Bool
    public var editedAt: Date?

    // ── Suppression ───────────────────────────────────────────
    public var isDeleted:       Bool
    public var deletedAt:       Date?
    public var isDeletedForAll: Bool

    // ── View Once ─────────────────────────────────────────────
    public var isViewOnce: Bool

    // ── Mentions ──────────────────────────────────────────────
    public var mentionedUserIds: [String]

    // ── Étoilé / Favoris ──────────────────────────────────────
    public var isStarred: Bool


    // ── Métadonnées ───────────────────────────────────────────
    public var createdAt: Date
    public var updatedAt: Date

    // ── Init ──────────────────────────────────────────────────

    public init(
        id:                      String                       = UUID().uuidString.lowercased(),
        conversationId:          String,
        groupId:                 String?                     = nil,
        senderId:                String,
        senderName:              String,
        senderPhone:             String                      = "",
        receiverId:              String                      = "",
        type:                    MessageTypeModel             = .text,
        content:                 MessageContentModel          = .text(""),
        searchText:              String?                      = nil,
        timestamp:               Date                        = Date(),
        deliveryStatus:          MessageDeliveryStatusModel   = .pending,
        replyToMessageId:        String?                      = nil,
        replyToSenderName:       String?                      = nil,
        replyToMessageType:      MessageTypeModel?            = nil,
        replyToMessagePreview:   String?                      = nil,
        replyToThumbnailURL:     String?                      = nil,
        replyToIsDeleted:        Bool?                        = nil,
        isForwarded:             Bool                         = false,
        forwardCount:            Int                          = 0,
        isEdited:                Bool                         = false,
        editedAt:                Date?                        = nil,
        isDeleted:               Bool                         = false,
        deletedAt:               Date?                        = nil,
        isDeletedForAll:         Bool                         = false,
        isViewOnce:              Bool                         = false,
        mentionedUserIds:        [String]                     = [],
        isStarred:               Bool                         = false,
        createdAt:               Date                        = Date(),
        updatedAt:               Date                        = Date()
    ) {
        self.id                      = id
        self.conversationId          = conversationId
        self.groupId                 = groupId
        self.senderId                = senderId
        self.senderName              = senderName
        self.senderPhone             = senderPhone
        self.receiverId              = receiverId
        self.type                    = type
        self.content                 = content
        self.searchText              = searchText
        self.timestamp               = timestamp
        self.deliveryStatus          = deliveryStatus
        self.replyToMessageId        = replyToMessageId
        self.replyToSenderName       = replyToSenderName
        self.replyToMessageType      = replyToMessageType
        self.replyToMessagePreview   = replyToMessagePreview
        self.replyToThumbnailURL     = replyToThumbnailURL
        self.replyToIsDeleted        = replyToIsDeleted
        self.isForwarded             = isForwarded
        self.forwardCount            = forwardCount
        self.isEdited                = isEdited
        self.editedAt                = editedAt
        self.isDeleted               = isDeleted
        self.deletedAt               = deletedAt
        self.isDeletedForAll         = isDeletedForAll
        self.isViewOnce              = isViewOnce
        self.mentionedUserIds        = mentionedUserIds
        self.isStarred               = isStarred
        self.createdAt               = createdAt
        self.updatedAt               = updatedAt
    }
}
