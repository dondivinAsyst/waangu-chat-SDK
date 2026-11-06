//
//  ReadReceiptModel.swift
//  AppModules
//
//  Created by Asyst on 6/24/26.
//

// FeatureChat/Data/Models/ReadReceiptModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: ReadReceiptModel
// ─────────────────────────────────────────────────────────────
// Accusé de réception par participant par message.
//
// Pas chargé systématiquement — stocké/fetché uniquement quand :
//   1. Le serveur envoie un batch de read receipts
//   2. L'utilisateur ouvre "Message Info"
//
// Le scroll utilise MessageModel.deliveryStatus (agrégé).
// Ce model est la source de vérité détaillée.
//
// ⚠️ Contrainte métier : UNIQUE(messageId, userId)

public struct ReadReceiptModel: Storable {
    public static let namespace        = "chat"
    public static let schemaVersion    = 1
    public static let indexedFields    = [
        "messageId",
        "conversationId",
        "userId",
    ]
    public static let searchableFields = [String]()
    public static let foreignKeys      = [
        StorableForeignKey("messageId", references: "chat_messagemodels", onDelete: .cascade)
    ]

    // ── Identité ──────────────────────────────────────────────
    public var id:             String
    public var messageId:      String        // codeMessage — same string as MessageModel.id
    public var conversationId: String        // dénormalisé — évite une jointure via message
    public var userId:         String        // ID backend du destinataire
    public var contactId:      String?       // lien local

    // ── Accusés ───────────────────────────────────────────────
    public var deliveredAt:    Date?         // ✓✓ gris — arrivé sur l'appareil
    public var readAt:         Date?         // ✓✓ bleu — ouvert et vu

    // ── Métadonnées ───────────────────────────────────────────
    public var createdAt:      Date
    public var updatedAt:      Date

    // ── Init ──────────────────────────────────────────────────

    public init(
        id:             String          = UUID().uuidString.lowercased(),
        messageId:      String,
        conversationId: String,
        userId:         String,
        contactId:      String?         = nil,
        deliveredAt:    Date?           = nil,
        readAt:         Date?           = nil,
        createdAt:      Date            = Date(),
        updatedAt:      Date            = Date()
    ) {
        self.id             = id
        self.messageId      = messageId
        self.conversationId = conversationId
        self.userId         = userId
        self.contactId      = contactId
        self.deliveredAt    = deliveredAt
        self.readAt         = readAt
        self.createdAt      = createdAt
        self.updatedAt      = updatedAt
    }
}
