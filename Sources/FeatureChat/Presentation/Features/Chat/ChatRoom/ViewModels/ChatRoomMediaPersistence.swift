//
//  ChatRoomMediaPersistence.swift
//  FeatureChat
//

import AVFoundation
import Foundation
import UIKit

/// Disk caching helpers for chat media (images, video, documents).
enum ChatRoomMediaPersistence {

    static let audioExtensions: Set<String> = ["mp3", "wav", "aac", "m4a", "ogg", "flac", "wma", "opus"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "3gp"]

    static func mimeType(for ext: String) -> String {
        let map: [String: String] = [
            "pdf": "application/pdf",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ppt": "application/vnd.ms-powerpoint",
            "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "txt": "text/plain",
            "rtf": "application/rtf",
            "csv": "text/csv",
            "zip": "application/zip",
            "mp3": "audio/mpeg",
            "mp4": "video/mp4",
            "mov": "video/quicktime",
            "png": "image/png",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
        ]
        return map[ext] ?? "application/octet-stream"
    }

    /// - Returns: `false` when a video could not be written to disk, which makes
    ///   the later upload fail with "Local file not found".
    @discardableResult
    static func saveCachedMedia(
        url: String,
        key: String,
        type: MediaType,
        image: UIImage?,
        jpegData: Data? = nil
    ) -> Bool {
        if type == .image {
            // Save JPEG data if available (preserves original compressed file size)
            if let jpegData = jpegData {
                DiskMediaManager.shared.saveImageDataToDisk(jpegData, fileName: key, pathName: .CHAT, asJPEG: true)
                return true
            }

            // Fallback: save UIImage as PNG (legacy behavior)
            //
            // The empty-image stand-in is load-bearing, however wrong it looks: the
            // upload path resolves its file by asking the disk for `key`, so if
            // nothing is written here there is nothing to upload and the message
            // never sends. Removing it stopped batches from sending at all.
            //
            // Logged rather than refused, so the real problem — a payload arriving
            // with no bytes — is visible without taking the send down with it.
            #if DEBUG
            if image == nil {
                print("[ChatRoomMediaPersistence] No image bytes to cache for \(key)")
            }
            #endif
            DiskMediaManager.shared.saveImageToDisk(image ?? UIImage(), fileName: key, pathName: .CHAT)
            return true
        }

        if type == .video {
            // Media URIs arrive as bare filesystem paths; see LocalMediaURL for
            // why URL(string:) cannot be used directly here.
            guard let videoURL = LocalMediaURL.resolve(url) else { return false }
            return DiskMediaManager.shared.saveVideoToDisk(from: videoURL, fileName: key, pathName: .CHAT)
        }

        return true
    }

    static func saveVideoThumbnailToDisk(base64: String, key: String) {
        let cleaned = base64
            .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
            .replacingOccurrences(of: "data:image/png;base64,", with: "")
        guard let data = Data(base64Encoded: cleaned),
              let image = UIImage(data: data) else { return }
        DiskMediaManager.shared.saveImageToDisk(image, fileName: key, pathName: .CHAT)
        ChatImageMemoryCache.shared.store(image, forKey: key)
    }

    static func generateVideoThumbnail(from url: URL, key: String) {
        Task.detached(priority: .utility) {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            let time = CMTime(seconds: 1, preferredTimescale: 60)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return }
            let thumb = UIImage(cgImage: cgImage)
            DiskMediaManager.shared.saveImageToDisk(thumb, fileName: key, pathName: .CHAT)
            ChatImageMemoryCache.shared.store(thumb, forKey: key)
        }
    }

    static func persistFile(from sourceURL: URL, code: String) -> String? {
        DiskMediaManager.shared.saveFileToDisk(from: sourceURL, fileName: code, pathName: .CHAT)?.absoluteString
    }
}
