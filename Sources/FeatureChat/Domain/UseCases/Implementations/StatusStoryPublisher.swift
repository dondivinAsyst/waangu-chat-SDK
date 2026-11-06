import Disk
import Foundation
import UIKit
import WaanguCoreKit
import WaanguNetworkKit

/// Single pipeline for publishing a status: local file upload (when needed) → `postOwnStatusToAPI`.
/// Media upload goes through `UploadFileUseCase` → `FileUploadRepository.uploadFileWithRetry`
/// (same presigned-URL path as chat attachments).
final class StatusStoryPublisher {
    private let repository: StatusRepositoryProtocol
    private let uploadFileUseCase: UploadFileUseCaseProtocol
    /// Statuts en cours de publication **dans ce processus**.
    private let inFlight = StatusPublishRegistry()

    init(
        repository: StatusRepositoryProtocol,
        uploadFileUseCase: UploadFileUseCaseProtocol
    ) {
        self.repository = repository
        self.uploadFileUseCase = uploadFileUseCase
    }

    // MARK: - Exclusivité

    /// Exécute `work` seulement si aucune publication de `itemId` n'est déjà en
    /// cours. Rend `false` sans rien faire sinon.
    ///
    /// Un statut vient d'être créé : sa publication part en tâche de fond, et
    /// il reste `.pending` puis `.syncing` le temps qu'elle aboutisse. Pendant
    /// ce temps, la reprise des statuts interrompus — lancée à chaque apparition
    /// de « Mon statut » — le voyait comme bloqué et le publiait une seconde
    /// fois. Le serveur créait le premier, refusait le second, et ce refus
    /// écrasait `.synced` par `.failed` : publié pour tout le monde, affiché en
    /// échec chez son auteur.
    ///
    /// À envelopper autour de **toute** l'opération de l'appelant, pas seulement
    /// de l'envoi : une reprise écrit `.retrying` avant de publier, et cette
    /// écriture, venue après le `.synced` de la vraie publication, laisserait
    /// le statut coincé.
    ///
    /// Après un arrêt de l'application, rien n'est en cours dans le nouveau
    /// processus : la reprise des statuts réellement interrompus fonctionne
    /// toujours.
    @discardableResult
    func exclusively(for itemId: String, _ work: () async throws -> Void) async rethrows -> Bool {
        try await inFlight.run(for: itemId, work)
    }

    // MARK: - Public entry points

    /// Saves media to disk before the item is written to GRDB (first-time create).
    func saveToDisk(story: StoryToSend) -> String? {
        switch story.type {
        case .image:
            guard let contentString = story.content,
                  let url = URL(string: contentString),
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return nil }
            DiskMediaManager.shared.saveImageToDisk(image, fileName: story.id, pathName: .STATUS)
            return PathName.STATUS.rawValue + "/\(story.id).png"

        case .video:
            guard let uri = story.PHMedia?.uri ?? story.content,
                  let url = URL(string: uri) else { return nil }
            DiskMediaManager.shared.saveVideoToDisk(from: url, fileName: story.id, pathName: .STATUS)
            // Persist poster so the stories strip shows a frame immediately.
            if let dataURL = story.thumbnail, let image = imageFromDataURL(dataURL) {
                DiskMediaManager.shared.saveImageToDisk(image, fileName: story.id, pathName: .STATUS)
            }
            return PathName.STATUS.rawValue + "/\(story.id).mp4"

        default:
            return nil
        }
    }

    /// Full pipeline after local persistence: upload media (if any) then POST to API.
    func uploadAndPublish(story: StoryToSend, item: StatusItem) async {
        var mutableStory = story
        debugLog("🛜 Status post start uploading")
        if mutableStory.type == .image || mutableStory.type == .video {
            guard let remoteURL = await uploadMediaIfNeeded(story: &mutableStory, item: item) else {
                return
            }
            mutableStory.content = remoteURL

            var uploadedItem = item
            uploadedItem.content = remoteURL
            uploadedItem.uploadedUrl = remoteURL
            uploadedItem.uploaded = true
            do {
                try await repository.updateStatusItem(uploadedItem)
                // Media is on the CDN — move past .pending so the badge isn't stuck if POST decode races.
                try? await repository.updateSyncStatus(for: item.codeStatus, to: .syncing, errorMessage: nil)
            } catch {
                await markFailed(itemId: item.codeStatus, reason: error.localizedDescription)
                return
            }
        }
        await publishToAPI(story: mutableStory, itemId: item.codeStatus)
    }

    /// POST only — media is already uploaded or this is a text status.
    func publishExisting(item: StatusItem) async {
        await publishToAPI(story: story(from: item), itemId: item.codeStatus)
    }

    func story(from item: StatusItem) -> StoryToSend {
        StoryToSend(
            id: item.codeStatus,
            userId: item.userId,
            type: item.type,
            content: item.content,
            caption: item.caption,
            background: item.background,
            fontText: item.fontText,
            fontWeight: item.fontWeight,
            expiresInHours: 24,
            thumbnail: item.thumbnail,
            userName: item.userName,
            userImage: item.userImage,
            fileSize: item.fileSize
        )
    }

    // MARK: - Private

    private func uploadMediaIfNeeded(story: inout StoryToSend, item: StatusItem) async -> String? {
        if item.uploaded, let content = item.content, !content.isEmpty {
            return content
        }

        guard let fileURL = resolveFileURL(story: story, item: item) else {
            await markFailed(itemId: item.codeStatus, reason: "Local file not found for upload")
            return nil
        }

        do {
            let fileData = try Data(contentsOf: fileURL)
            let request = FileUploadRequest(
                fileName: resolvedFileName(for: item, fileURL: fileURL),
                fileType: resolvedMimeType(for: item, fileURL: fileURL),
                fileSize: fileData.count,
                folder: .story
            )
            let result = await uploadFileUseCase.execute(for: request, fileData: fileData)

            switch result {
            case .success(let remoteURL):
                return remoteURL
            case .failure(let error):
                await markFailed(itemId: item.codeStatus, reason: error.localizedDescription)
                return nil
            }
        } catch {
            await markFailed(itemId: item.codeStatus, reason: error.localizedDescription)
            return nil
        }
    }

    private func resolveFileURL(story: StoryToSend, item: StatusItem) -> URL? {
        switch story.type {
        case .video:
            return DiskMediaManager.shared.loadVideoFromDisk(fileName: item.codeStatus, pathName: .STATUS)
        case .image:
            return DiskMediaManager.shared.imageURL(for: item.codeStatus, pathName: .STATUS)
                ?? URL(string: story.content ?? "")
        default:
            return nil
        }
    }

    private func resolvedFileName(for item: StatusItem, fileURL: URL) -> String {
        if let filename = item.filename, !filename.isEmpty {
            return filename
        }
        return fileURL.lastPathComponent
    }

    private func resolvedMimeType(for item: StatusItem, fileURL: URL) -> String {
        if let mimeType = item.mimeType, !mimeType.isEmpty {
            return mimeType
        }
        switch fileURL.pathExtension.lowercased() {
        case "mp4", "mov":
            return "video/mp4"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        default:
            return item.type == .video ? "video/mp4" : "image/jpeg"
        }
    }

    private func publishToAPI(story: StoryToSend, itemId: String) async {
        do {
            try await repository.updateSyncStatus(for: itemId, to: .syncing, errorMessage: nil)
            let response = try await repository.postOwnStatusToAPI(story)
            if !response.isSuccess {
                debugLog("❌ Status post rejected by server (\(response.status)): \(response.message)")
            }
        } catch {
            debugLog("❌ Status post threw error: \(error.localizedDescription)")
        }
    }

    private func markFailed(itemId: String, reason: String) async {
        do {
            try await repository.updateSyncStatus(for: itemId, to: .failed, errorMessage: reason)
        } catch {
            debugLog("❌ Failed to mark status as failed: \(error)")
        }
    }
}

// MARK: - Registre des publications en cours

/// Les identifiants de statut dont la publication est en cours.
///
/// Acteur : la création et la reprise tournent dans des tâches concurrentes, et
/// la vérification « déjà en cours ? » doit être atomique avec la prise.
actor StatusPublishRegistry {

    private var ids: Set<String> = []

    /// `true` si `work` a été exécuté ; `false` s'il était déjà en cours pour
    /// cet identifiant. L'identifiant est libéré même si `work` lève.
    func run(for id: String, _ work: () async throws -> Void) async rethrows -> Bool {
        guard ids.insert(id).inserted else {
            debugLog("⏭️ Status \(id) already publishing — duplicate publish skipped")
            return false
        }
        do {
            try await work()
        } catch {
            ids.remove(id)
            throw error
        }
        ids.remove(id)
        return true
    }

    func isRunning(_ id: String) -> Bool { ids.contains(id) }
}
