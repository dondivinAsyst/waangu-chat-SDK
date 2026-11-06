// FeatureChat/Data/Models/StatusViewerModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: StatusViewerModel
// ─────────────────────────────────────────────────────────────
// Qui a vu quel segment de statut et quand.
// Même pattern que ReadReceiptModel :
//   - StatusModel.viewCount = compteur dénormalisé (affichage rapide)
//   - StatusViewerModel = détail "qui a vu" (+ réaction éventuelle)
//
// Fetché quand l'utilisateur swipe vers le haut
// sur son propre statut pour voir la liste des vues.
//
// ⚠️ Contrainte métier : UNIQUE(statusId, userId)

public struct StatusViewerModel: Storable {
    public static let namespace        = "chat"
    public static let schemaVersion    = 2
    public static let indexedFields    = [
        "statusId",
        "userId",
        "viewedAt",
    ]
    public static let searchableFields = [String]()
    public static let foreignKeys      = [
        StorableForeignKey("statusId", references: "chat_statusmodels", onDelete: .cascade)
    ]

    // ── Identité ──────────────────────────────────────────────
    public var id:        String
    public var statusId:  String           // quel segment a été vu
    public var userId:    String           // qui a vu
    public var contactId: String?          // lien local

    // ── Dénormalisé (affichage sans jointure) ─────────────────
    public var userName:  String
    public var avatarURL: String?

    // ── Vue / réaction ────────────────────────────────────────
    public var viewedAt:  Date             // quand il a vu
    /// Emoji from `STORY_REACTED` (`ReactToStoryPayload.reaction`). Nil until they react.
    public var reaction:  String?

    // ── Métadonnées ───────────────────────────────────────────
    public var createdAt: Date
    public var updatedAt: Date

    // ── Init ──────────────────────────────────────────────────

    public init(
        id:        String  = UUID().uuidString.lowercased(),
        statusId:  String,
        userId:    String,
        contactId: String? = nil,
        userName:  String,
        avatarURL: String? = nil,
        viewedAt:  Date    = Date(),
        reaction:  String? = nil,
        createdAt: Date    = Date(),
        updatedAt: Date    = Date()
    ) {
        self.id        = id
        self.statusId  = statusId
        self.userId    = userId
        self.contactId = contactId
        self.userName  = userName
        self.avatarURL = avatarURL
        self.viewedAt  = viewedAt
        self.reaction  = reaction
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
