// FeatureChat/Data/DTOs/CreateStatusDTO.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: CreateStatusRequestDTO
// ─────────────────────────────────────────────────────────────
// REST : POST /api/status (multipart/form-data)
// Le fichier média est envoyé séparément en multipart.
// Ce DTO représente les métadonnées JSON accompagnant l'upload.

public struct CreateStatusRequestDTO: Codable, Sendable {

    // ── Identité ──────────────────────────────────────────────
    public let id:        String             // UUID généré localement
    public let mediaType: String             // "text", "image", "video"

    // ── Contenu ───────────────────────────────────────────────
    public let text:    String?              // contenu pour statut texte
    public let caption: String?              // légende pour image/vidéo

    // ── Apparence (statuts texte) ─────────────────────────────
    public let backgroundColor: String?      // couleur de fond hex
    public let fontStyle:       String?      // style de police

    // ── Ordre ─────────────────────────────────────────────────
    public let segmentIndex:  Int            // position dans la story (0, 1, 2...)
    public let totalSegments: Int            // nombre total de segments

    // ── Visibilité ────────────────────────────────────────────
    public let privacy:        String        // "allContacts", "selectedContacts", "allExcept"
    public let allowedUserIds:  [String]?    // si privacy = "selectedContacts"
    public let excludedUserIds: [String]?    // si privacy = "allExcept"
}

// ─────────────────────────────────────────────────────────────
// MARK: CreateStatusResponseDTO
// ─────────────────────────────────────────────────────────────
// Réponse serveur après upload réussi.
// Le serveur retourne les URLs des fichiers uploadés
// et le timestamp officiel.

public struct CreateStatusResponseDTO: Codable, Sendable {

    // ── Identité ──────────────────────────────────────────────
    public let statusId:  String             // confirmé par le serveur
    public let timestamp: Double             // epoch — horloge serveur

    // ── URLs générées par le serveur ──────────────────────────
    public let mediaURL:     String?         // URL du fichier original
    public let thumbnailURL: String?         // miniature générée par le serveur

    // ── Dimensions (calculées par le serveur) ─────────────────
    public let width:           Int?
    public let height:          Int?
    public let durationSeconds: Double?      // durée vidéo

    // ── Expiration ────────────────────────────────────────────
    public let expiresAt: Double             // epoch — postedAt + 24h
}
