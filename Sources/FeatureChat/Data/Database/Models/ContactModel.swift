// FeatureChat/Data/Models/ContactModel.swift
import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: ContactModel
// ─────────────────────────────────────────────────────────────
// Profil d'un utilisateur connu.
//
// Ce qui N'EST PAS ici :
//   isMuted / wallpaper / lock  → ChatPreferenceModel (par phone)
//   presenceStatus / isOnline   → mémoire (RealtimeKit, fire-and-forget)
//   deliveredAt / readAt        → ReadReceiptModel (par message)
//
// Seul lastSeenAt est persisté ("vu à 14h32").

public struct ContactModel: Storable {
    public static let namespace        = "chat"
    public static let schemaVersion    = 1
    public static let indexedFields    = [
        "userId",
        "phone",
        "isBlocked",
        "isRegistered",
        "isFavorite",
        "lastSeenAt",
    ]
    public static let searchableFields = ["name", "phone", "username"]
    public static let foreignKeys: [StorableForeignKey] = []

    // ── Identité ──────────────────────────────────────────────
    public var id:        String
    public var userId:    String           // ID backend
    public var phone:     String           // "+257..." — clé de déduplication
    public var name:      String           // nom affiché
    public var username:  String?          // @username
    public var avatarURL: String?
    public var bio:       String?          // "Hey there! I am using Waangu"

    // ── Présence (seul lastSeenAt est persisté) ───────────────
    public var lastSeenAt: Date?

    // ── Statut plateforme ─────────────────────────────────────
    public var isRegistered:   Bool        // inscrit sur Waangu
    public var isVerified:     Bool        // badge ✓
    public var isBlocked:      Bool
    public var isFavorite:     Bool        // favoris / contacts fréquents
    public var isSavedContact: Bool        // dans le carnet du téléphone

    // ── Privacy (ce que ce contact me montre) ─────────────────
    public var showLastSeen:     Bool
    public var showProfilePhoto: Bool
    public var showStatus:       Bool

    // ── Métadonnées ───────────────────────────────────────────
    public var createdAt: Date
    public var updatedAt: Date

    // ── Init ──────────────────────────────────────────────────

    public init(
        id:               String  = UUID().uuidString.lowercased(),
        userId:           String,
        phone:            String,
        name:             String,
        username:         String? = nil,
        avatarURL:        String? = nil,
        bio:              String? = nil,
        lastSeenAt:       Date?   = nil,
        isRegistered:     Bool    = true,
        isVerified:       Bool    = false,
        isBlocked:        Bool    = false,
        isFavorite:       Bool    = false,
        isSavedContact:   Bool    = false,
        showLastSeen:     Bool    = true,
        showProfilePhoto: Bool    = true,
        showStatus:       Bool    = true,
        createdAt:        Date    = Date(),
        updatedAt:        Date    = Date()
    ) {
        self.id               = id
        self.userId           = userId
        self.phone            = phone
        self.name             = name
        self.username         = username
        self.avatarURL        = avatarURL
        self.bio              = bio
        self.lastSeenAt       = lastSeenAt
        self.isRegistered     = isRegistered
        self.isVerified       = isVerified
        self.isBlocked        = isBlocked
        self.isFavorite       = isFavorite
        self.isSavedContact   = isSavedContact
        self.showLastSeen     = showLastSeen
        self.showProfilePhoto = showProfilePhoto
        self.showStatus       = showStatus
        self.createdAt        = createdAt
        self.updatedAt        = updatedAt
    }
}
