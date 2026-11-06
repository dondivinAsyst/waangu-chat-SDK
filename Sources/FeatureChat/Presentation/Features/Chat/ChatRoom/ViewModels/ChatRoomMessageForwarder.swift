//
//  ChatRoomMessageForwarder.swift
//  FeatureChat
//

import Foundation
import UIKit

/// Prepares selected messages for a forward: a new message code per copy, the
/// on-disk media duplicated under it, and content stripped of the original's
/// transfer bookkeeping.
enum ChatRoomMessageForwarder {

    struct MediaAccess {
        let cachedImage: (String) -> UIImage?
        let cachedMediaURL: (String) -> URL?
    }

    /// One forwarded copy, ready to hand to the send pipeline. The pipeline
    /// builds the outgoing message itself, so only what it needs is carried:
    /// the code the media was copied under, the type, and the content.
    struct Payload {
        let code: String
        let type: MessageTypeProps
        let content: MessageContent
    }

    static func newMessageCode() -> String {
        OutgoingMessageBuilder.newCode()
    }

    static func payloads(
        for originals: [MessageDataItem],
        mediaAccess: MediaAccess
    ) -> [Payload] {
        originals.map { original in
            let code = newMessageCode()
            copyMediaFiles(from: original, to: code, mediaAccess: mediaAccess)
            return Payload(
                code: code,
                type: original.typeMessage,
                content: forwardedContent(of: original)
            )
        }
    }

    /// The original's content, minus anything that describes the original's own
    /// transfer.
    ///
    /// Settled media already points at the URL it was uploaded to, and the copy
    /// can reuse it — a forward never re-uploads. What must not carry over is a
    /// pending or failed transfer flag, which would leave the new message
    /// waiting on an upload that already happened.
    private static func forwardedContent(of original: MessageDataItem) -> MessageContent {
        var content = original.message
        content.shouldUploadDownload = false
        content.shouldRetry = false
        content.autoTransferAttempts = nil
        return content
    }

    static func copyMediaFiles(
        from original: MessageDataItem,
        to code: String,
        mediaAccess: MediaAccess
    ) {
        switch original.typeMessage {
        case .IMAGE:
            if let cachedImage = mediaAccess.cachedImage(original.codeMessage) {
                ChatRoomMediaPersistence.saveCachedMedia(
                    url: "",
                    key: code,
                    type: .image,
                    image: cachedImage
                )
            }

        case .VIDEO, .VIDEO_NOTE:
            if let cachedVideo = mediaAccess.cachedMediaURL(original.codeMessage) {
                DiskMediaManager.shared.saveVideoToDisk(from: cachedVideo, fileName: code, pathName: .CHAT)
            }
            if let cachedThumbnail = mediaAccess.cachedImage(original.codeMessage) {
                DiskMediaManager.shared.saveImageToDisk(cachedThumbnail, fileName: code, pathName: .CHAT)
            }

        case .AUDIO, .VOICE, .DOCUMENT:
            if let fileName = original.message.fileName {
                let ext = (fileName as NSString).pathExtension.lowercased()
                if let sourceURL = DiskMediaManager.shared.loadFileFromDisk(
                    fileName: original.codeMessage,
                    ext: ext,
                    pathName: .CHAT
                ) {
                    _ = DiskMediaManager.shared.saveFileToDisk(
                        from: sourceURL,
                        fileName: code,
                        pathName: .CHAT
                    )
                }
            }

        default:
            break
        }
    }
}
