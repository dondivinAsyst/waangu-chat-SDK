// FeatureChat/Data/Models/PinnedMessageModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: PinnedMessageModel
// ─────────────────────────────────────────────────────────────
// Message épinglé dans une conversation.
// Telegram affiche une barre cliquable en haut du chat.
// WhatsApp affiche un bandeau avec navigation entre épinglés.
//
// Un message peut être épinglé/désépinglé par un admin.
// Plusieurs messages peuvent être épinglés simultanément.
// L'ordre d'affichage est par pinnedAt DESC (dernier épinglé en premier).
//
// Dénormalisation : messagePreview et senderName stockés
// pour afficher la barre sans jointure sur MessageModel.

public struct PinnedMessageModel: Storable {
    public static let namespace        = "chat"
    public static let schemaVersion    = 1
    public static let indexedFields    = [
        "conversationId",
        "messageId",
        "pinnedAt",
    ]
    public static let searchableFields = [String]()
    public static let foreignKeys      = [
        StorableForeignKey("conversationId", references: "chat_conversationmodels", onDelete: .cascade),
        StorableForeignKey("messageId", references: "chat_messagemodels", onDelete: .cascade),
    ]

    // ── Identité ──────────────────────────────────────────────
    public var id:             String
    public var conversationId: String
    public var messageId:      String            // codeMessage — same string as MessageModel.id

    // ── Dénormalisé (affichage barre sans jointure) ───────────
    public var messagePreview: String?           // "Salut !", "Photo", "Document"
    public var messageType:    MessageTypeModel  // pour l'icône dans la barre
    public var senderName:     String            // qui a écrit le message épinglé

    // ── Qui a épinglé ─────────────────────────────────────────
    public var pinnedByUserId: String            // ID backend de celui qui a épinglé
    public var pinnedByName:   String            // dénormalisé "Épinglé par Alice"
    public var pinnedAt:       Date              // tri par date

    // ── Métadonnées ───────────────────────────────────────────
    public var createdAt:      Date
    public var updatedAt:      Date

    // ── Init ──────────────────────────────────────────────────

    public init(
        id:              String          = UUID().uuidString.lowercased(),
        conversationId:  String,
        messageId:       String,
        messagePreview:  String?         = nil,
        messageType:     MessageTypeModel = .text,
        senderName:      String,
        pinnedByUserId:  String,
        pinnedByName:    String,
        pinnedAt:        Date            = Date(),
        createdAt:       Date            = Date(),
        updatedAt:       Date            = Date()
    ) {
        self.id              = id
        self.conversationId  = conversationId
        self.messageId       = messageId
        self.messagePreview  = messagePreview
        self.messageType     = messageType
        self.senderName      = senderName
        self.pinnedByUserId  = pinnedByUserId
        self.pinnedByName    = pinnedByName
        self.pinnedAt        = pinnedAt
        self.createdAt       = createdAt
        self.updatedAt       = updatedAt
    }
}
