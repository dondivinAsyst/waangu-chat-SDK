//
//  ChatRoomGallerySendCoordinator.swift
//  FeatureChat
//

import Foundation
import Photos

/// Sends gallery picks (images/videos) with thumbnail generation off the main thread.
enum ChatRoomGallerySendCoordinator {

    struct Handlers {
        let sendMedia: @MainActor (MediaPayload, String?, String) -> Void
    }

    static func sendImages(
        caption: String?,
        selectedImages: [GalleryImage],
        handlers: Handlers
    ) {
        guard !selectedImages.isEmpty else { return }
        let groupId = UUID().uuidString.lowercased()

        for image in selectedImages {
            Task.detached(priority: .userInitiated) {
                await withCheckedContinuation { continuation in
                    generateAndSaveThumbnail(for: image.asset) { thumbnailPath, fullImage, jpegData in
                        Task { @MainActor in
                            if let path = thumbnailPath {
                                var payload = MediaPayload(
                                    thumbnail: path,
                                    image: image.uri ?? "",
                                    fileName: image.fileName ?? "",
                                    caption: image.caption ?? "",
                                    size: image.size ?? 0,
                                    mimeType: image.mimeType ?? ""
                                )
                                payload.uiImage = fullImage
                                payload.jpegData = jpegData
                                payload.width = image.asset.pixelWidth
                                payload.height = image.asset.pixelHeight
                                handlers.sendMedia(payload, caption, groupId)
                            }
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    static func sendMediaItems(
        caption: String?,
        selectedMedia: [GalleryMedia],
        handlers: Handlers
    ) {
        guard !selectedMedia.isEmpty else { return }
        let groupId = UUID().uuidString.lowercased()

        for media in selectedMedia {
            Task.detached(priority: .userInitiated) {
                await withCheckedContinuation { continuation in
                    generateAndSaveThumbnail(for: media.asset) { thumbnailPath, fullImage, jpegData in
                        Task { @MainActor in
                            if let path = thumbnailPath {
                                var payload = MediaPayload(
                                    thumbnail: path,
                                    image: media.uri ?? "",
                                    fileName: media.fileName ?? "",
                                    caption: media.caption ?? "",
                                    size: media.size ?? 0,
                                    mimeType: media.mimeType ?? "",
                                    mediaType: media.type
                                )
                                payload.uiImage = fullImage
                                payload.jpegData = jpegData
                                payload.width = media.asset.pixelWidth
                                payload.height = media.asset.pixelHeight
                                handlers.sendMedia(payload, caption, groupId)
                            }
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }
}
