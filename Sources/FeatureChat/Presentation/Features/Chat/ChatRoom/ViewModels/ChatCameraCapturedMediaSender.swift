//
//  ChatCameraCapturedMediaSender.swift
//  FeatureChat
//

import AVFoundation
import Foundation
import UIKit

enum ChatCameraCapturedMediaSender {

    static func makeImagePayload(image: UIImage, caption: String, jpegData: Data?, useHD: Bool = false) -> MediaPayload {
        let maxBytes = useHD ? ChatImageSendEncoder.hdMaxBytes : ChatImageSendEncoder.standardMaxBytes
        let data: Data
        if let jpegData, !jpegData.isEmpty, jpegData.count <= maxBytes {
            data = jpegData
        } else {
            data = ChatImageSendEncoder.encode(image, useHD: useHD)
        }
        // Explicit preview format rather than the helper's defaults, which are
        // tuned for status thumbnails. See `ChatMediaPreviewFormat`.
        let base64 = imageToDataURL(
            image,
            quality: ChatMediaPreviewFormat.quality,
            maxDimension: ChatMediaPreviewFormat.maxDimension
        ) ?? ""
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try? data.write(to: tempURL)

        return MediaPayload(
            thumbnail: base64,
            image: tempURL.absoluteString,
            fileName: tempURL.lastPathComponent,
            caption: caption,
            size: data.count,
            mimeType: "image/jpeg",
            mediaType: .image,
            uiImage: image,
            jpegData: data,
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale)
        )
    }

    static func makeVideoPayload(url: URL, caption: String) -> MediaPayload {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let thumb = generateVideoThumbnailBase64(from: url) ?? ""
        let dimensions = videoDimensions(of: url)

        return MediaPayload(
            thumbnail: thumb,
            image: url.absoluteString,
            fileName: url.lastPathComponent,
            caption: caption,
            size: fileSize,
            mimeType: "video/mp4",
            mediaType: .video,
            width: dimensions.map { Int($0.width) },
            height: dimensions.map { Int($0.height) }
        )
    }

    /// Display dimensions of a video, with its orientation applied.
    ///
    /// `naturalSize` alone is the raw encoded size, so a portrait clip recorded on
    /// a phone reports landscape — the rotation lives in the track's transform.
    /// Sent so the receiver can size the bubble before the video is downloaded.
    private static func videoDimensions(of url: URL) -> CGSize? {
        guard let track = AVAsset(url: url).tracks(withMediaType: .video).first else { return nil }
        let displaySize = track.naturalSize.applying(track.preferredTransform)
        let size = CGSize(width: abs(displaySize.width), height: abs(displaySize.height))
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }

    private static func generateVideoThumbnailBase64(from url: URL) -> String? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Pull a frame at preview resolution — `imageToDataURL` only shrinks, so a
        // smaller frame here would cap the preview below the intended size.
        generator.maximumSize = CGSize(
            width: ChatMediaPreviewFormat.maxDimension,
            height: ChatMediaPreviewFormat.maxDimension
        )
        let time = CMTime(seconds: 0.5, preferredTimescale: 60)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return imageToDataURL(
            UIImage(cgImage: cgImage),
            quality: ChatMediaPreviewFormat.quality,
            maxDimension: ChatMediaPreviewFormat.maxDimension
        )
    }
}
