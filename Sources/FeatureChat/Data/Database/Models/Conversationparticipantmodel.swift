// FeatureChat/Data/Models/ConversationParticipantModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: ConversationParticipantModel
// ─────────────────────────────────────────────────────────────
// Table pivot N-N entre Conversation et Contact.
// Utilisé pour TOUS les types de conversation :
//
//   Direct  → exactement 2 participants, role = .member
//             Sert à résoudre "ma conversation avec Alice"
//
//   Groupe  → N participants avec rôles (owner/admin/member)
//             Sert à lister les membres, gérer les permissions
//
//   Channel → N participants, tous .member (lecture seule)
//
// Réintégration : si un membre quitte et revient, un NOUVEL
// enregistrement est créé. L'ancien (leftAt != nil) reste
// pour l'historique ("Alice a quitté le groupe").
//
// ⚠️ Contrainte métier : UNIQUE(conversationId, userId)
//    Vérifiée dans le repository avant insert.

public struct ConversationParticipantModel: Storable {
    public static let namespace        = "chat"
    public static let schemaVersion    = 1
    public static let indexedFields    = [
        "conversationId",
        "userId",
        "contactId",
        "phone",
        "role",
        "leftAt",
    ]
    public static let searchableFields = ["displayName", "phone"]
    public static let foreignKeys      = [
        StorableForeignKey("conversationId", references: "chat_conversationmodels", onDelete: .cascade)
    ]

    // ── Identité ──────────────────────────────────────────────
    public var id:             String
    public var conversationId: String
    public var userId:         String       // ID backend — source de vérité, toujours présent
    public var contactId:      String?       // lien local — nil si pas encore dans mes contacts
    public var phone:          String       // dénormalisé pour résolution directe

    // ── Rôle ──────────────────────────────────────────────────
    public var role: ParticipantRoleModel

    // ── Affichage ─────────────────────────────────────────────
    public var displayName:  String         // nom affiché (peut différer du contact en groupe)
    public var avatarURL:    String?
    public var customColor:  String?        // couleur du nom dans le groupe

    // ── Lifecycle ─────────────────────────────────────────────
    public var joinedAt:         Date
    public var addedByUserId:    String?    // ID backend de celui qui a ajouté
    public var leftAt:           Date?      // nil = actif, non nil = parti/exclu
    public var removedByUserId:  String?    // ID backend de celui qui a exclu
    public var leaveReason:      LeaveReasonModel?

    // ── Sync ──────────────────────────────────────────────────
//    public var syncStatus: SyncStatusModel

    // ── Métadonnées ───────────────────────────────────────────
    public var createdAt: Date
    public var updatedAt: Date

    // ── Propriétés calculées ──────────────────────────────────

    public var isActive: Bool { leftAt == nil }
    public var isAdmin:  Bool { role == .admin || role == .owner }

    // ── Init ──────────────────────────────────────────────────

    public init(
        id:               String             = UUID().uuidString.lowercased(),
        conversationId:   String,
        userId:           String,
        contactId:        String?            = nil,
        phone:            String,
        role:             ParticipantRoleModel = .member,
        displayName:      String,
        avatarURL:        String?            = nil,
        customColor:      String?            = nil,
        joinedAt:         Date               = Date(),
        addedByUserId:    String?            = nil,
        leftAt:           Date?              = nil,
        removedByUserId:  String?            = nil,
        leaveReason:      LeaveReasonModel?  = nil,
//        syncStatus:       SyncStatusModel    = .pending,
        createdAt:        Date               = Date(),
        updatedAt:        Date               = Date()
    ) {
        self.id               = id
        self.conversationId   = conversationId
        self.userId           = userId
        self.contactId        = contactId
        self.phone            = phone
        self.role             = role
        self.displayName      = displayName
        self.avatarURL        = avatarURL
        self.customColor      = customColor
        self.joinedAt         = joinedAt
        self.addedByUserId    = addedByUserId
        self.leftAt           = leftAt
        self.removedByUserId  = removedByUserId
        self.leaveReason      = leaveReason
        self.createdAt        = createdAt
        self.updatedAt        = updatedAt
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: ParticipantRoleModel
// ─────────────────────────────────────────────────────────────

public enum ParticipantRoleModel: String, Codable, Sendable, CaseIterable {
    case owner          // créateur — un seul par groupe
    case admin          // peut gérer membres + paramètres
    case member         // participant standard

    public var hierarchy: Int {
        switch self {
        case .owner:  return 3
        case .admin:  return 2
        case .member: return 1
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: LeaveReasonModel
// ─────────────────────────────────────────────────────────────

public enum LeaveReasonModel: String, Codable, Sendable {
    case voluntary      // "Alice a quitté le groupe"
    case removed        // "Alice a été exclu par Bob"
    case banned         // "Alice a été banni du groupe"
}
