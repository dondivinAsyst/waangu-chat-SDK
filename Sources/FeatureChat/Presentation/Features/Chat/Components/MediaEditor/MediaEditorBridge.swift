//
//  MediaEditorBridge.swift
//  FeatureChat
//

import AVFoundation
import Photos
import SwiftUI
import UIKit

enum MediaEditorBridge {

    // MARK: - Path Normalization
    
    /// Converts bare video paths from PHMediaManager into proper file:// URLs.
    /// Fixes: PHMediaManager stores bare paths like "/var/mobile/Media/DCIM/…" which
    /// URL(string:) treats as schemeless relative URLs. This normalizes them to file URLs.
    static func normalizeVideoPath(_ path: String?) -> URL? {
        guard let path = path else { return nil }
        
        // Already a URL scheme (file://, http://, etc.)
        if path.hasPrefix("file://") || path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        
        // Absolute path on disk → add file:// scheme
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        
        // Last resort: try as-is
        return URL(string: path)
    }

    // MARK: - PreviewMediaItem → editor state

    static func makeEditorState(from preview: PreviewMediaItem) -> (MediaItem, MediaInfo)? {
        switch preview.source {
        case .gallery(let galleryMedia):
            return makeFromGallery(galleryMedia)
        case .captured(let captured):
            return makeFromCaptured(captured)
        }
    }

    private static func makeFromGallery(_ galleryMedia: GalleryMedia) -> (MediaItem, MediaInfo)? {
        switch galleryMedia.type {
        case .image:
            guard let image = galleryMedia.highQualityImage else { return nil }
            let item = MediaItem(
                image: image,
                type: .image,
                PHMedia: galleryMedia,
                fileSize: galleryMedia.size ?? 0
            )
            return (item, freshMediaInfo(for: item))

        case .video:
            let thumb = galleryMedia.highQualityImage ?? UIImage()
            // Use normalized path → fixes URL(string:) on bare paths
            let video = videoItem(
                url: normalizeVideoPath(galleryMedia.uri),
                pHAsset: galleryMedia.asset
            )
            let item = MediaItem(
                image: thumb,
                video: video,
                type: .video,
                PHMedia: galleryMedia,
                fileSize: galleryMedia.size ?? 0
            )
            return (item, freshMediaInfo(for: item))
        }
    }

    private static func makeFromCaptured(_ captured: CapturedCameraMedia) -> (MediaItem, MediaInfo)? {
        switch captured {
        case .image(let image, _):
            let item = MediaItem(image: image, type: .image, fileSize: 0)
            return (item, freshMediaInfo(for: item))

        case .video(let url), .videoNote(let url):
            let thumb = thumbnailForVideo(url: url) ?? UIImage()
            let video = videoItem(url: url)
            let item = MediaItem(image: thumb, video: video, type: .video, fileSize: 0)
            return (item, freshMediaInfo(for: item))
        }
    }

    static func freshMediaInfo(for item: MediaItem) -> MediaInfo {
        MediaInfo(
            media: item,
            originalMedia: item,
            imageFilter: .none,
            overLayText: "",
            captionText: "",
            selectedTextColor: .white,
            selectedFontIndex: 0,
            lines: [],
            drawSelectedColor: .white,
            selectedLineWidth: 5,
            textScale: 1.0,
            lastScale: 1.0,
            textOffset: .zero,
            lastOffset: .zero,
            textPosition: .zero
        )
    }

    static func hasEdits(_ info: MediaInfo) -> Bool {
        info.imageFilter != .none
            || info.cropSession != nil
            || !info.lines.isEmpty
            || !info.overLayText.isEmpty
    }

    static func fittedImageRect(forImageSize imageSize: CGSize, inFrameSize frameSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              frameSize.width > 0, frameSize.height > 0 else { return .zero }

        let imageAspect = imageSize.width / imageSize.height
        let frameAspect = frameSize.width / frameSize.height

        let drawSize: CGSize
        if imageAspect > frameAspect {
            drawSize = CGSize(width: frameSize.width, height: frameSize.width / imageAspect)
        } else {
            drawSize = CGSize(width: frameSize.height * imageAspect, height: frameSize.height)
        }

        let origin = CGPoint(
            x: (frameSize.width - drawSize.width) / 2,
            y: (frameSize.height - drawSize.height) / 2
        )
        return CGRect(origin: origin, size: drawSize)
    }

    private static func thumbnailForVideo(url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        guard let cgImage = try? generator.copyCGImage(
            at: CMTime(seconds: 0.5, preferredTimescale: 60),
            actualTime: nil
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
