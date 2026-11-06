// FeatureChat/Data/Models/MessageReactionModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: MessageReactionModel
// ─────────────────────────────────────────────────────────────
// Une réaction = un emoji d'un utilisateur sur un message.
// Un utilisateur ne peut mettre qu'UN seul emoji par message.
// Changer d'emoji = update, pas delete + insert.
// Retirer une réaction = hard delete (comme WhatsApp).
//
// ⚠️ Contrainte métier : UNIQUE(messageId, userId)
//    Vérifiée dans le repository avant insert.

public struct MessageReactionModel: Storable {
    public static let namespace        = "chat"
    public static let schemaVersion    = 1
    public static let indexedFields    = [
        "messageId",
        "userId",
        "emoji",
    ]
    public static let searchableFields = [String]()
    public static let foreignKeys      = [
        StorableForeignKey("messageId", references: "chat_messagemodels", onDelete: .cascade)
    ]

    // ── Identité ──────────────────────────────────────────────
    public var id:        String
    public var messageId: String         // codeMessage — same string as MessageModel.id
    public var userId:    String         // ID backend
    public var contactId: String?        // ID contact local — nil si pas dans mes contacts
    public var userName:  String         // dénormalisé pour l'affichage

    // ── Réaction ──────────────────────────────────────────────
    public var emoji:     String         // "👍", "❤️", "😂", "👍🏽" (skin tone inclus)

    // ── Sync ──────────────────────────────────────────────────
//    public var syncStatus: SyncStatusModel

    // ── Métadonnées ───────────────────────────────────────────
    public var createdAt: Date
    public var updatedAt: Date           // mis à jour quand l'emoji change

    // ── Init ──────────────────────────────────────────────────

    public init(
        id:         String          = UUID().uuidString.lowercased(),
        messageId:  String,
        userId:     String,
        contactId:  String?         = nil,
        userName:   String,
        emoji:      String,
        createdAt:  Date            = Date(),
        updatedAt:  Date            = Date()
    ) {
        self.id         = id
        self.messageId  = messageId
        self.userId     = userId
        self.contactId  = contactId
        self.userName   = userName
        self.emoji      = emoji
        self.createdAt  = createdAt
        self.updatedAt  = updatedAt
    }
}
