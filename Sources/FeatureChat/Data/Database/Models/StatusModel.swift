// FeatureChat/Data/Models/StatusModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: StatusModel
// ─────────────────────────────────────────────────────────────
// Story éphémère 24h — onglet "Statuts".
// Un segment par record. Groupement par userId dans le ViewModel.
// Expiré = expiresAt < now → nettoyé par job périodique.
// Supprimé manuellement = deletedAt != nil.

public struct StatusModel: Storable {
    public static let namespace        = "chat"
    /// Keep in sync with `ChatDatabaseRegistration` StatusModel FieldMigrations (latest → 3).
    public static let schemaVersion    = 3
    public static let indexedFields    = [
        "userId",
        "postedAt",
        "expiresAt",
        "mediaType",
        "segmentIndex",
        "viewed",
        "syncStatus",   // ← required: getPendingSyncStatuses filters on this column
        // Media upload metadata — needed to reconstruct FileUploadRequest on retry
        "filename",
        "fileSize",
        "localPath",    // disk-cache path (relative), used to re-read file data on retry
    ]
    public static let searchableFields = [String]()
    public static let foreignKeys: [StorableForeignKey] = []

    // ── Identité ──────────────────────────────────────────────
    public var id:        String
    public var userId:    String
    public var contactId: String?

    // ── Dénormalisé ───────────────────────────────────────────
    public var userName:  String
    public var avatarURL: String?

    // ── Ordre dans la story ───────────────────────────────────
    public var segmentIndex:  Int           // 0, 1, 2... position dans la story
    public var totalSegments: Int           // nombre total (dénormalisé pour "3/5")

    // ── Contenu ───────────────────────────────────────────────
    public var mediaType:       StatusMediaTypeModel
    public var text:            String?     // contenu pour les statuts texte
    public var caption:         String?     // légende pour image/vidéo
    public var linkURL:         String?     // lien cliquable
    public var mediaURL:        String?
    public var thumbnailURL:    String?
    public var localPath:       String?
    public var mimeType:        String?

    // ── Apparence (statuts texte) ─────────────────────────────
    public var backgroundColor: String?     // couleur de fond hex
    public var fontStyle:       String?     // style de police
    public var fontSize:        Int?
    public var fontWeight:      String?

    // ── Dimensions (image/vidéo) ──────────────────────────────
    public var width:           Int?
    public var height:          Int?
    public var durationSeconds: Double?

    // ── Visibilité ────────────────────────────────────────────
    public var privacy:         StatusPrivacyModel
    public var allowedUserIds:  [String]?
    public var excludedUserIds: [String]?

    // ── Interactions ──────────────────────────────────────────
    public var viewCount:       Int          // compteur dénormalisé
    public var viewed:       Bool

    // ── Lifecycle ─────────────────────────────────────────────
    public var postedAt:        Date
    public var expiresAt:       Date         // postedAt + 24h
    public var deletedAt:       Date?        // supprimé manuellement avant expiration

    // ── Computed ──────────────────────────────────────────────
    public var isExpired: Bool { Date() > expiresAt }

    // ── Sync ──────────────────────────────────────────────────
    public var syncStatus:      SyncStatusModel

    // ── Upload metadata (needed to rebuild FileUploadRequest on retry) ──────
    public var filename:        String?    // original file name, e.g. "IMG-abc.jpg"
    public var fileSize:        Int        // bytes — 0 until known

    // ── Métadonnées ───────────────────────────────────────────
    public var createdAt:       Date
    public var updatedAt:       Date

    // ── Init ──────────────────────────────────────────────────

    public init(
        id:              String              = UUID().uuidString.lowercased(),
        userId:          String,
        contactId:       String?             = nil,
        userName:        String,
        avatarURL:       String?             = nil,
        segmentIndex:    Int                 = 0,
        totalSegments:   Int                 = 1,
        mediaType:       StatusMediaTypeModel,
        text:            String?             = nil,
        caption:         String?             = nil,
        linkURL:         String?             = nil,
        mediaURL:        String?             = nil,
        thumbnailURL:    String?             = nil,
        localPath:       String?             = nil,
        mimeType:        String?             = nil,
        backgroundColor: String?             = nil,
        fontStyle:       String?             = nil,
        fontSize:        Int?                = nil,
        fontWeight:      String?             = nil,
        width:           Int?                = nil,
        height:          Int?                = nil,
        durationSeconds: Double?             = nil,
        privacy:         StatusPrivacyModel  = .allContacts,
        allowedUserIds:  [String]?           = nil,
        excludedUserIds: [String]?           = nil,
        viewCount:       Int                 = 0,
        viewed:          Bool                = false,
        postedAt:        Date                = Date(),
        expiresAt:       Date?               = nil,
        deletedAt:       Date?               = nil,
        syncStatus:      SyncStatusModel     = .pending,
        filename:        String?             = nil,
        fileSize:        Int                 = 0,
        createdAt:       Date                = Date(),
        updatedAt:       Date                = Date()
    ) {
        self.id              = id
        self.userId          = userId
        self.contactId       = contactId
        self.userName        = userName
        self.avatarURL       = avatarURL
        self.segmentIndex    = segmentIndex
        self.totalSegments   = totalSegments
        self.mediaType       = mediaType
        self.text            = text
        self.caption         = caption
        self.linkURL         = linkURL
        self.mediaURL        = mediaURL
        self.thumbnailURL    = thumbnailURL
        self.localPath       = localPath
        self.mimeType        = mimeType
        self.backgroundColor = backgroundColor
        self.fontStyle       = fontStyle
        self.fontSize        = fontSize
        self.fontWeight      = fontWeight
        self.width           = width
        self.height          = height
        self.durationSeconds = durationSeconds
        self.privacy         = privacy
        self.allowedUserIds  = allowedUserIds
        self.excludedUserIds = excludedUserIds
        self.viewCount       = viewCount
        self.viewed          = viewed
        self.postedAt        = postedAt
        self.expiresAt       = expiresAt ?? postedAt.addingTimeInterval(24 * 60 * 60)
        self.deletedAt       = deletedAt
        self.syncStatus      = syncStatus
        self.filename        = filename
        self.fileSize        = fileSize
        self.createdAt       = createdAt
        self.updatedAt       = updatedAt
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: StatusMediaTypeModel
// ─────────────────────────────────────────────────────────────

public enum StatusMediaTypeModel: String, Codable, Sendable {
    case text
    case image
    case video
}

// ─────────────────────────────────────────────────────────────
// MARK: StatusPrivacyModel
// ─────────────────────────────────────────────────────────────

public enum StatusPrivacyModel: String, Codable, Sendable {
    case allContacts
    case selectedContacts
    case allExcept
}
