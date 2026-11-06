import Foundation
import UIKit
import WaanguCoreKit

/// Resolves status media from the on-device cache (own + contact stories).
enum StatusLocalMediaResolver {
    static func isOwnStatus(_ item: StatusItem) -> Bool {
        item.userId == CurrentSessionInfo.shared.currentUid
    }

    static func diskImage(for item: StatusItem) -> UIImage? {
        DiskMediaManager.shared.loadImageFromDisk(fileName: item.codeStatus, pathName: .STATUS)
    }

    static func diskVideoURL(for item: StatusItem) -> URL? {
        DiskMediaManager.shared.loadVideoFromDisk(fileName: item.codeStatus, pathName: .STATUS)
    }

    /// Prefer disk cache for any status (own or contact); fall back to persisted `content`.
    static func playbackURL(for item: StatusItem) -> URL? {
        if let local = diskVideoURL(for: item) {
            return local
        }
        return remoteContentURL(for: item)
    }

    /// Background-cache a remote status video after playback starts.
    /// Also stores a poster frame under the same `codeStatus` so strip previews can refresh.
    static func cacheRemoteVideoIfNeeded(for item: StatusItem) {
        let codeStatus = item.codeStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !codeStatus.isEmpty else { return }
        guard let remoteURL = remoteContentURL(for: item), !remoteURL.isFileURL else { return }

        let needsVideo = !DiskMediaManager.shared.hasDiskVideo(for: codeStatus, pathName: .STATUS)
        let needsPoster = !DiskMediaManager.shared.hasDiskImage(for: codeStatus, pathName: .STATUS)
        guard needsVideo || needsPoster else { return }

        Task.detached(priority: .utility) {
            do {
                if needsVideo {
                    let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        return
                    }
                    _ = DiskMediaManager.shared.copyVideoToDisk(
                        from: tempURL,
                        fileName: codeStatus,
                        pathName: .STATUS
                    )
                }

                if needsPoster {
                    let posterSource = DiskMediaManager.shared.loadVideoFromDisk(
                        fileName: codeStatus,
                        pathName: .STATUS
                    ) ?? remoteURL
                    if let poster = await generateThumbnail(url: posterSource) {
                        DiskMediaManager.shared.saveImageToDisk(
                            poster,
                            fileName: codeStatus,
                            pathName: .STATUS
                        )
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .statusMediaCached,
                                object: codeStatus
                            )
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("Status video cache failed (\(codeStatus)): \(error)")
                #endif
            }
        }
    }

    /// Cache a poster for a video that is already playing (local or remote).
    static func cacheVideoPosterIfNeeded(for item: StatusItem, from url: URL?) {
        let codeStatus = item.codeStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !codeStatus.isEmpty else { return }
        guard !DiskMediaManager.shared.hasDiskImage(for: codeStatus, pathName: .STATUS) else { return }
        guard let url else { return }

        Task.detached(priority: .utility) {
            if let poster = await generateThumbnail(url: url) {
                DiskMediaManager.shared.saveImageToDisk(
                    poster,
                    fileName: codeStatus,
                    pathName: .STATUS
                )
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .statusMediaCached,
                        object: codeStatus
                    )
                }
            }
        }
    }

    private static func remoteContentURL(for item: StatusItem) -> URL? {
        guard let content = item.content?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&"),
              !content.isEmpty else {
            return nil
        }
        return URL(string: content)
    }

    // MARK: - Strip / offline preview

    /// Resolved still for status cards (strip, My Status list).
    struct StripPreview {
        let diskImage: UIImage?
        let remoteURL: URL?
        let isImageDataUrl: Bool

        var usesDisk: Bool { diskImage != nil }
    }

    /// Own status: local disk / file only (never compressed payload thumbnail).
    /// Contact status: disk → thumbnail (base64 or https) → image content URL.
    static func stripPreview(for item: StatusItem, ownLocalOnly: Bool) -> StripPreview {
        if let disk = diskImage(for: item) {
            return StripPreview(diskImage: disk, remoteURL: nil, isImageDataUrl: false)
        }

        if ownLocalOnly {
            if let local = loadLocalStill(for: item) {
                return StripPreview(diskImage: local, remoteURL: nil, isImageDataUrl: false)
            }
            return StripPreview(diskImage: nil, remoteURL: nil, isImageDataUrl: false)
        }

        if let thumb = decodeThumbnailStill(item.thumbnail) {
            return StripPreview(diskImage: thumb, remoteURL: nil, isImageDataUrl: false)
        }

        if let remoteThumb = remoteThumbnailURL(item.thumbnail) {
            return StripPreview(diskImage: nil, remoteURL: remoteThumb, isImageDataUrl: false)
        }

        // Contact image without separate thumbnail — use content URL.
        if item.type == .image, let contentURL = remoteContentURL(for: item), !contentURL.isFileURL {
            return StripPreview(diskImage: nil, remoteURL: contentURL, isImageDataUrl: false)
        }

        return StripPreview(diskImage: nil, remoteURL: nil, isImageDataUrl: false)
    }

    /// Decode thumbnail for viewer overlays (loading / offline video).
    static func thumbnailStill(for item: StatusItem) -> UIImage? {
        if let disk = diskImage(for: item) { return disk }
        return decodeThumbnailStill(item.thumbnail)
    }

    private static func loadLocalStill(for item: StatusItem) -> UIImage? {
        if let content = item.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: content),
           url.isFileURL,
           let image = UIImage(contentsOfFile: url.path),
           image.size.width > 0 {
            return image
        }
        return nil
    }

    private static func remoteThumbnailURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let cleaned = raw.cleanedBase64
        guard cleaned.lowercased().hasPrefix("http://")
                || cleaned.lowercased().hasPrefix("https://") else {
            return nil
        }
        return URL(string: cleaned.replacingOccurrences(of: "&amp;", with: "&"))
    }

    private static func decodeThumbnailStill(_ raw: String?) -> UIImage? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let cleaned = raw.cleanedBase64
        if cleaned.lowercased().hasPrefix("http://")
            || cleaned.lowercased().hasPrefix("https://") {
            return nil
        }
        if cleaned.hasPrefix("data:"), let image = imageFromDataURL(cleaned) {
            return image
        }
        return decodeBase64ToUIImage(cleaned)
    }
}
