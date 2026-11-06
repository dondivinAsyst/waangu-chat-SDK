//
//  ChatRoomMediaSendCoordinator.swift
//  FeatureChat
//

import Foundation

/// Builds media message content and caches sent video on disk.
enum ChatRoomMediaSendCoordinator {

    static func makeContent(from media: MediaPayload, caption: String? = nil, batchId: String? = nil) -> MessageContent {
        let isVideo = media.mediaType == .video
        var content = MessageContent(
            image: isVideo ? nil : media.image,
            UIimage: isVideo ? nil : media.uiImage,
            shouldUploadDownload: true,
            shouldRetry: false,
            video: isVideo ? media.image : nil,
            fileName: media.fileName,
            size: media.size,
            width: media.width,
            height: media.height,
            thumbnail: media.thumbnail,
            caption: caption,
            mimeType: media.mimeType,
            mediaBatchId: batchId
        )
        // Store jpegData in a separate field for caching (not part of the message entity)
        // Passed to validateAndCacheImage via the MediaPayload
        return content
    }

    /// - Returns: `false` when the payload carried no usable bytes, so the caller
    ///   can say so rather than letting it surface later as a missing file.
    @discardableResult
    static func cacheImageFromPayload(_ media: MediaPayload, code: String) -> Bool {
        // Save the original JPEG data if available (preserves real compressed file size)
        // Falls back to UIImage as PNG if jpegData not available (legacy behavior)
        return ChatRoomMediaPersistence.saveCachedMedia(
            url: media.image,
            key: code,
            type: .image,
            image: media.uiImage,
            jpegData: media.jpegData
        )
    }

    /// - Returns: `false` when the video could not be cached to disk, so the
    ///   caller can surface the failure instead of letting the upload die later
    ///   with "Local file not found".
    @discardableResult
    static func cacheSentVideo(media: MediaPayload, code: String) -> Bool {
        let saved = ChatRoomMediaPersistence.saveCachedMedia(
            url: media.image,
            key: code,
            type: .video,
            image: nil
        )

        if !media.thumbnail.isEmpty {
            ChatRoomMediaPersistence.saveVideoThumbnailToDisk(base64: media.thumbnail, key: code)
        }

        // Generate from the cached copy when available: the source path may be a
        // PHAsset export that is cleaned up once the send completes.
        let thumbnailSource = DiskMediaManager.shared.loadVideoFromDisk(fileName: code, pathName: .CHAT)
            ?? LocalMediaURL.resolve(media.image)

        if let thumbnailSource {
            ChatRoomMediaPersistence.generateVideoThumbnail(from: thumbnailSource, key: code)
        }

        return saved
    }
}
