// FeatureChat/Data/Models/ChatPreferenceModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: ChatPreferenceModel
// ─────────────────────────────────────────────────────────────
// Préférences par cible — identifiée par (targetType, targetKey).
//
//   direct       → targetKey = phone ("+257790000000")
//   conversation → targetKey = conversationId
//
// Existe AVANT et APRÈS la création de la conversation.
// Zéro doublon : un phone = un enregistrement, toujours.
// Zéro migration phoneNumber→contact : le phone ne change pas.

public struct ChatPreferenceModel: Storable {
    public static let namespace        = "chat"
    public static let schemaVersion    = 1
    public static let indexedFields    = ["targetKey", "targetType", "isLocked"]
    public static let searchableFields = ["targetKey"]
    public static let foreignKeys:     [StorableForeignKey] = []

    // ── Clé métier UNIQUE(targetType, targetKey) ──────────────
    public var id:         String
    public var targetType: PreferenceTargetTypeModel
    public var targetKey:  String

    // ── Notifications ─────────────────────────────────────────
    public var isMuted:          Bool
    public var mutedUntil:       Date?
    public var customTone:       String?
    public var vibrationPattern: String?
    public var showPreviews:     Bool

    // ── Apparence ─────────────────────────────────────────────
    public var wallpaperName:   String?
    public var wallpaperURL:    String?
    public var isDarkTheme:     Bool?
    public var chatBubbleColor: String?
    public var fontSize:        ChatFontSizeModel?

    // ── Médias ────────────────────────────────────────────────
    public var showInGallery:        Bool
    public var autoDownloadPhotos:   Bool
    public var autoDownloadVideos:   Bool
    public var autoDownloadDocuments: Bool

    // ── Sécurité ──────────────────────────────────────────────
    public var isLocked:    Bool
    public var lockTimeout: Int?

    // ── Messages éphémères ────────────────────────────────────
    public var disappearingMessagesSeconds: Int?
    
    // -- Pinned --
    public var isPinned: Bool

    // ── Métadonnées ───────────────────────────────────────────
    public var createdAt: Date
    public var updatedAt: Date
    

    // ── Init direct — par numéro de téléphone ─────────────────

    public init(
        phone:                       String,
        isMuted:                     Bool              = false,
        mutedUntil:                  Date?             = nil,
        customTone:                  String?           = nil,
        vibrationPattern:            String?           = nil,
        showPreviews:                Bool              = true,
        wallpaperName:               String?           = nil,
        wallpaperURL:                String?           = nil,
        isDarkTheme:                 Bool?             = nil,
        chatBubbleColor:             String?           = nil,
        fontSize:                    ChatFontSizeModel? = nil,
        showInGallery:               Bool              = true,
        autoDownloadPhotos:          Bool              = true,
        autoDownloadVideos:          Bool              = false,
        autoDownloadDocuments:       Bool              = true,
        isLocked:                    Bool              = false,
        lockTimeout:                 Int?              = nil,
        disappearingMessagesSeconds: Int?              = nil,
        isPinned:                    Bool              = false,
        createdAt:                   Date              = Date(),
        updatedAt:                   Date              = Date()
    ) {
        self.id                          = UUID().uuidString.lowercased()
        self.targetType                  = .direct
        self.targetKey                   = phone
        self.isMuted                     = isMuted
        self.mutedUntil                  = mutedUntil
        self.customTone                  = customTone
        self.vibrationPattern            = vibrationPattern
        self.showPreviews                = showPreviews
        self.wallpaperName               = wallpaperName
        self.wallpaperURL                = wallpaperURL
        self.isDarkTheme                 = isDarkTheme
        self.chatBubbleColor             = chatBubbleColor
        self.fontSize                    = fontSize
        self.showInGallery               = showInGallery
        self.autoDownloadPhotos          = autoDownloadPhotos
        self.autoDownloadVideos          = autoDownloadVideos
        self.autoDownloadDocuments       = autoDownloadDocuments
        self.isLocked                    = isLocked
        self.lockTimeout                 = lockTimeout
        self.disappearingMessagesSeconds = disappearingMessagesSeconds
        self.isPinned                    = isPinned
        self.createdAt                   = createdAt
        self.updatedAt                   = updatedAt
    }

    // ── Init conversation — par conversationId ────────────────

    public init(
        conversationId:              String,
        isMuted:                     Bool              = false,
        mutedUntil:                  Date?             = nil,
        customTone:                  String?           = nil,
        vibrationPattern:            String?           = nil,
        showPreviews:                Bool              = true,
        wallpaperName:               String?           = nil,
        wallpaperURL:                String?           = nil,
        isDarkTheme:                 Bool?             = nil,
        chatBubbleColor:             String?           = nil,
        fontSize:                    ChatFontSizeModel? = nil,
        showInGallery:               Bool              = true,
        autoDownloadPhotos:          Bool              = true,
        autoDownloadVideos:          Bool              = false,
        autoDownloadDocuments:       Bool              = true,
        isLocked:                    Bool              = false,
        lockTimeout:                 Int?              = nil,
        disappearingMessagesSeconds: Int?              = nil,
        isPinned:                    Bool              = false,
        createdAt:                   Date              = Date(),
        updatedAt:                   Date              = Date()
    ) {
        self.id                          = UUID().uuidString.lowercased()
        self.targetType                  = .conversation
        self.targetKey                   = conversationId
        self.isMuted                     = isMuted
        self.mutedUntil                  = mutedUntil
        self.customTone                  = customTone
        self.vibrationPattern            = vibrationPattern
        self.showPreviews                = showPreviews
        self.wallpaperName               = wallpaperName
        self.wallpaperURL                = wallpaperURL
        self.isDarkTheme                 = isDarkTheme
        self.chatBubbleColor             = chatBubbleColor
        self.fontSize                    = fontSize
        self.showInGallery               = showInGallery
        self.autoDownloadPhotos          = autoDownloadPhotos
        self.autoDownloadVideos          = autoDownloadVideos
        self.autoDownloadDocuments       = autoDownloadDocuments
        self.isLocked                    = isLocked
        self.lockTimeout                 = lockTimeout
        self.disappearingMessagesSeconds = disappearingMessagesSeconds
        self.isPinned                    = isPinned
        self.createdAt                   = createdAt
        self.updatedAt                   = updatedAt
    }
}
