//
//  ResumableUpload.swift
//  CoreKit
//
//  Envoi de médias segmenté et reprenable — Bloc 8, §21.
//
//  **BACKEND CONTRACT REQUIRED** — `POST /v1/uploads` (§24), reprise par
//  intervalle d'octets.
//
//  `UploadProgressTracker` (NetworkKit) suit une progression ; il ne reprend
//  rien. Un envoi interrompu à 90 % repart aujourd'hui de zéro, ce qui sur un
//  réseau instable veut dire : ne se termine jamais.
//

import Foundation

// MARK: - Point de reprise (§21)

/// Où en est un envoi.
public struct UploadCheckpoint: Codable, Sendable, Hashable {

    public let uploadID: String

    /// Empreinte du fichier **entier**.
    ///
    /// Le champ décisif. Reprendre un envoi sans vérifier que le fichier est
    /// toujours le même recolle la fin d'un fichier à la tête d'un autre — le
    /// serveur assemble alors un objet qui n'a jamais existé, et son empreinte
    /// finale ne correspond à rien. Une photo réencodée par le système suffit
    /// à déclencher le cas.
    public let fileHash: String

    public var uploadedBytes: Int64
    public let totalBytes: Int64

    /// Taille de segment retenue. Fixée à la création : la changer en cours de
    /// route décale les frontières et corrompt l'assemblage.
    public let chunkSize: Int64

    public let createdAt: Date
    public var lastProgressAt: Date

    public init(uploadID: String, fileHash: String, uploadedBytes: Int64 = 0,
                totalBytes: Int64, chunkSize: Int64 = 1_048_576,
                createdAt: Date = Date(), lastProgressAt: Date = Date()) {
        self.uploadID = uploadID
        self.fileHash = fileHash
        self.uploadedBytes = uploadedBytes
        self.totalBytes = totalBytes
        self.chunkSize = chunkSize
        self.createdAt = createdAt
        self.lastProgressAt = lastProgressAt
    }

    public var progress: Double {
        totalBytes > 0 ? Double(uploadedBytes) / Double(totalBytes) : 0
    }

    public var isComplete: Bool { uploadedBytes >= totalBytes }

    /// L'intervalle du prochain segment.
    public var nextRange: Range<Int64>? {
        guard !isComplete else { return nil }
        return uploadedBytes..<min(uploadedBytes + chunkSize, totalBytes)
    }

    /// Ce point de reprise vaut-il encore pour ce fichier ?
    ///
    /// - Parameter currentHash: empreinte recalculée à la reprise, jamais celle
    ///   mémorisée — sinon le contrôle se compare à lui-même.
    public func isValid(for currentHash: String, now: Date = Date(),
                        maximumAge: TimeInterval = 86_400) -> Bool {
        fileHash == currentHash
            && uploadedBytes <= totalBytes
            && now.timeIntervalSince(createdAt) <= maximumAge
    }
}

// MARK: - Contraintes (§21)

/// Ce qu'on accepte d'envoyer.
public struct UploadConstraints: Sendable, Hashable {

    public let maximumBytes: Int64

    /// Types acceptés, en MIME.
    public let allowedMIMETypes: Set<String>

    /// L'envoi doit être chiffré avant de partir.
    public let requiresEncryption: Bool

    public init(maximumBytes: Int64, allowedMIMETypes: Set<String>,
                requiresEncryption: Bool = false) {
        self.maximumBytes = maximumBytes
        self.allowedMIMETypes = allowedMIMETypes
        self.requiresEncryption = requiresEncryption
    }

    public static let image = UploadConstraints(
        maximumBytes: 10 * 1_048_576,
        allowedMIMETypes: ["image/jpeg", "image/png", "image/heic", "image/webp"]
    )

    public static let video = UploadConstraints(
        maximumBytes: 100 * 1_048_576,
        allowedMIMETypes: ["video/mp4", "video/quicktime"]
    )

    public static let document = UploadConstraints(
        maximumBytes: 25 * 1_048_576,
        allowedMIMETypes: ["application/pdf"]
    )

    /// Pièce jointe à un objet financier — reçu, justificatif.
    public static let financialDocument = UploadConstraints(
        maximumBytes: 25 * 1_048_576,
        allowedMIMETypes: ["application/pdf", "image/jpeg", "image/png"],
        requiresEncryption: true
    )
}

/// Pourquoi un fichier est refusé.
public enum UploadRejection: String, Error, Sendable, Hashable, CaseIterable {

    case tooLarge          = "TOO_LARGE"
    case disallowedType    = "DISALLOWED_TYPE"

    /// Le contenu ne correspond pas au type annoncé.
    ///
    /// Refus distinct de ``disallowedType`` : celui-ci signale une *tentative*.
    /// Un fichier annoncé `image/png` dont les premiers octets disent autre
    /// chose n'est pas une erreur d'utilisateur.
    case contentTypeMismatch = "CONTENT_TYPE_MISMATCH"

    case empty             = "EMPTY"

    /// Le point de reprise ne correspond plus au fichier.
    case checkpointStale   = "CHECKPOINT_STALE"

    public var messageKey: String { "upload.rejected.\(rawValue.lowercased())" }

    public var isSecurityIncident: Bool { self == .contentTypeMismatch }
}

// MARK: - Validation du type réel

/// Reconnaît un type à partir des premiers octets.
///
/// Le type annoncé par le client et l'extension du fichier sont tous deux
/// sous le contrôle de celui qui envoie. Seul le contenu ne l'est pas.
public enum MagicByteValidator {

    /// Signatures, par type MIME.
    private static let signatures: [String: [[UInt8]]] = [
        "image/jpeg":      [[0xFF, 0xD8, 0xFF]],
        "image/png":       [[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]],
        "image/webp":      [[0x52, 0x49, 0x46, 0x46]],           // "RIFF"
        "application/pdf": [[0x25, 0x50, 0x44, 0x46]],           // "%PDF"
        "video/mp4":       [[0x66, 0x74, 0x79, 0x70]],           // "ftyp", à l'offset 4
        "video/quicktime": [[0x66, 0x74, 0x79, 0x70]]
    ]

    /// Décalage de la signature dans le fichier.
    private static let offsets: [String: Int] = [
        "video/mp4": 4,
        "video/quicktime": 4
    ]

    /// Le contenu correspond-il au type annoncé ?
    ///
    /// Rend `true` pour un type dont aucune signature n'est connue : ce
    /// validateur constate une contradiction, il ne prétend pas reconnaître
    /// tout. Refuser ce qu'il ne connaît pas bloquerait des formats légitimes
    /// pour cause d'ignorance, ce qui n'apporte aucune sécurité.
    public static func matches(declaredMIME: String, header: [UInt8]) -> Bool {
        guard let candidates = signatures[declaredMIME] else { return true }
        let offset = offsets[declaredMIME] ?? 0

        return candidates.contains { signature in
            guard header.count >= offset + signature.count else { return false }
            return Array(header[offset..<(offset + signature.count)]) == signature
        }
    }

    /// Combien d'octets suffisent au contrôle.
    public static let requiredHeaderBytes = 16
}

public extension UploadConstraints {

    /// Vérifie taille, type annoncé et type réel.
    ///
    /// - Parameter header: les premiers ``MagicByteValidator/requiredHeaderBytes``
    ///   octets. Passer `nil` saute le contrôle de contenu — à ne faire que
    ///   lorsqu'il a déjà eu lieu en amont.
    func rejection(forSize bytes: Int64, mimeType: String,
                   header: [UInt8]? = nil) -> UploadRejection? {
        guard bytes > 0 else { return .empty }
        guard bytes <= maximumBytes else { return .tooLarge }
        guard allowedMIMETypes.contains(mimeType) else { return .disallowedType }

        if let header, !MagicByteValidator.matches(declaredMIME: mimeType, header: header) {
            return .contentTypeMismatch
        }
        return nil
    }
}

// MARK: - Priorité (§22.9)

/// Ce qui passe en premier quand la bande passante manque.
///
/// Le §22.9 place le texte avant les médias, et la raison est concrète : une
/// photo de dix mégaoctets qui monopolise la liaison retarde tous les messages
/// écrits derrière elle. Sur un réseau à 2G, cela veut dire des minutes.
public enum UploadPriority: Int, Sendable, Comparable, CaseIterable {

    /// Sécurité et statut financier.
    case critical = 0

    /// Message texte.
    case text     = 1

    /// Miniature — assez légère pour partir avec le texte.
    case thumbnail = 2

    /// Média complet.
    case media    = 3

    /// Analytique, télémétrie.
    case deferred = 4

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Contrat

/// Envoie un fichier par segments, avec reprise.
public protocol ResumableUploading: Sendable {

    /// Ouvre un envoi. Rend le point de reprise initial.
    func begin(fileHash: String, totalBytes: Int64, mimeType: String,
               constraints: UploadConstraints,
               priority: UploadPriority) async -> Result<UploadCheckpoint, UploadRejection>

    /// Envoie le segment suivant et rend le point de reprise avancé.
    func sendNextChunk(_ checkpoint: UploadCheckpoint,
                       data: Data) async -> Result<UploadCheckpoint, SyncError>

    /// Reprend un envoi interrompu.
    ///
    /// Interroge le serveur pour savoir ce qu'il a **réellement** reçu, plutôt
    /// que de faire confiance au compteur local : un segment parti sans réponse
    /// a pu arriver. Repartir du compteur local le renverrait.
    func resume(uploadID: String,
                currentFileHash: String) async -> Result<UploadCheckpoint, SyncError>

    /// Clôt l'envoi et rend l'identifiant du média côté serveur.
    func finish(_ checkpoint: UploadCheckpoint) async -> Result<String, SyncError>

    /// Abandonne et libère les temporaires des deux côtés.
    func cancel(uploadID: String) async

    /// Supprime les fichiers temporaires des envois périmés (§21).
    func purgeStaleTemporaries(olderThan: TimeInterval) async -> Int
}

// MARK: - Défaut fermé

/// N'envoie rien.
public struct ClosedResumableUploader: ResumableUploading {

    public init() {}

    public func begin(fileHash: String, totalBytes: Int64, mimeType: String,
                      constraints: UploadConstraints,
                      priority: UploadPriority) async -> Result<UploadCheckpoint, UploadRejection> {
        // Refus par la contrainte la plus explicite dont on dispose ici.
        .failure(.disallowedType)
    }

    public func sendNextChunk(_ checkpoint: UploadCheckpoint,
                              data: Data) async -> Result<UploadCheckpoint, SyncError> {
        .failure(.serverUnavailable(retryAfter: nil))
    }

    public func resume(uploadID: String,
                       currentFileHash: String) async -> Result<UploadCheckpoint, SyncError> {
        .failure(.serverUnavailable(retryAfter: nil))
    }

    public func finish(_ checkpoint: UploadCheckpoint) async -> Result<String, SyncError> {
        .failure(.serverUnavailable(retryAfter: nil))
    }

    public func cancel(uploadID: String) async {}

    public func purgeStaleTemporaries(olderThan: TimeInterval) async -> Int { 0 }
}
