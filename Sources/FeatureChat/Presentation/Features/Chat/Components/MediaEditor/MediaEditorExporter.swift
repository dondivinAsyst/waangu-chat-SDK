//
//  MediaEditorExporter.swift
//  FeatureChat
//

import AVFoundation
import WaanguCoreKit
import Photos
import WaanguSharedUI
import SwiftUI
import UIKit

enum MediaEditorExporter {

    // MARK: - Export entry

    @MainActor
    static func export(
        preview: PreviewMediaItem,
        mediaInfo: MediaInfo,
        mediaItem: MediaItem,
        containerSize: CGSize,
        fontSize: CGFloat,
        addTextOnImage: Bool,
        isDragging: Bool,
        useHD: Bool,
        translationService: (any TranslationServiceProtocol)?
    ) async -> EditedMediaResult {
        switch mediaItem.type {
        case .image:
            return exportImage(
                preview: preview,
                mediaInfo: mediaInfo,
                containerSize: containerSize,
                fontSize: fontSize,
                addTextOnImage: addTextOnImage,
                isDragging: isDragging,
                useHD: useHD,
                translationService: translationService
            )
        case .video:
            return await exportVideo(
                preview: preview,
                mediaInfo: mediaInfo,
                mediaItem: mediaItem,
                containerSize: containerSize,
                useHD: useHD
            )
        case .none:
            return fallbackResult(for: preview, useHD: useHD)
        }
    }

    // MARK: - Image

    @MainActor
    private static func exportImage(
        preview: PreviewMediaItem,
        mediaInfo: MediaInfo,
        containerSize: CGSize,
        fontSize: CGFloat,
        addTextOnImage: Bool,
        isDragging: Bool,
        useHD: Bool,
        translationService: (any TranslationServiceProtocol)?
    ) -> EditedMediaResult {
        let sourceImage: UIImage? = {
            if MediaEditorBridge.hasEdits(mediaInfo), let edited = mediaInfo.media?.image {
                return edited
            }
            if let image = mediaInfo.media?.image { return image }
            if case .gallery(let media) = preview.source { return media.highQualityImage }
            if case .captured(.image(let image, _)) = preview.source { return image }
            return nil
        }()

        guard let baseImage = sourceImage else {
            return fallbackResult(for: preview, useHD: useHD)
        }

        let finalImage: UIImage
        if MediaEditorBridge.hasEdits(mediaInfo) {
            let renderSize = mediaInfo.imageRenderedSize.width > 0
                ? mediaInfo.imageRenderedSize
                : containerSize

            let exportView = GeometryReader { geo in
                FilteredImageView(
                    path: mediaInfo.media?.image,
                    filter: mediaInfo.imageFilter,
                    hideCanvas: true,
                    currentInfo: .constant(mediaInfo),
                    addTextOnImage: .constant(addTextOnImage),
                    fontSize: .constant(fontSize),
                    isDraging: .constant(isDragging),
                    geo: geo,
                    translationService: translationService
                )
            }
            .frame(width: containerSize.width, height: containerSize.height)

            let background = exportView.asUIImage(size: renderSize)
            finalImage = compositeLines(
                lines: mediaInfo.lines,
                onto: background,
                size: renderSize
            )
        } else {
            finalImage = baseImage
        }

        let jpegData = ChatImageSendEncoder.encode(finalImage, useHD: useHD)
        return .exportedImage(finalImage, jpegData: jpegData)
    }

    // MARK: - Video

    private static func exportVideo(
        preview: PreviewMediaItem,
        mediaInfo: MediaInfo,
        mediaItem: MediaItem,
        containerSize: CGSize,
        useHD: Bool
    ) async -> EditedMediaResult {
        let asset = await resolveVideoAsset(preview: preview, mediaItem: mediaItem)
        guard let asset else {
            debugLog("Video export failed: could not resolve AVAsset")
            return fallbackResult(for: preview, useHD: useHD)
        }

        let trimRange = await videoTrimRange(for: asset, mediaItem: mediaItem)
        let compressedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        do {
            let encodedURL = try await ChatVideoSendEncoder.encode(
                asset: asset,
                timeRange: trimRange,
                useHD: useHD,
                outputURL: compressedURL
            )

            let hasOverlays = !mediaInfo.lines.isEmpty || !mediaInfo.overLayText.isEmpty
            guard hasOverlays else {
                return .exportedVideo(encodedURL)
            }

            return await composeOverlays(
                videoURL: encodedURL,
                mediaInfo: mediaInfo,
                containerSize: containerSize
            )
        } catch {
            debugLog("Video export failed: \(error.localizedDescription)")
            return fallbackResult(for: preview, useHD: useHD)
        }
    }

    private static func resolveVideoAsset(
        preview: PreviewMediaItem,
        mediaItem: MediaItem
    ) async -> AVAsset? {
        // PREFER PHAsset when available (handles iCloud, permissions, etc.)
        if let phAsset = mediaItem.PHMedia?.asset ?? mediaItem.video?.pHAsset {
            if let asset = await loadAVAsset(from: phAsset), await hasVideoTrack(asset) {
                return asset
            }
            debugLog("Video asset from PHAsset has no video track or failed to load")
        }
        
        // CAPTURED video (always a local file URL)
        if case .captured(.video(let url)) = preview.source {
            let asset = AVAsset(url: url)
            if await hasVideoTrack(asset) {
                return asset
            }
            debugLog("Captured video has no video track: \(url.path)")
        }
        
        // FALLBACK to URL if present (but validate it has tracks)
        if let url = mediaItem.video?.url {
            let asset = AVAsset(url: url)
            if await hasVideoTrack(asset) {
                return asset
            }
            debugLog("Video URL has no video track: \(url.path)")
        }
        
        // LAST RESORT: try normalizing URI path
        if let uri = mediaItem.PHMedia?.uri {
            if let url = MediaEditorBridge.normalizeVideoPath(uri) {
                let asset = AVAsset(url: url)
                if await hasVideoTrack(asset) {
                    return asset
                }
                debugLog("Video URI normalized but has no video track: \(uri)")
            } else {
                debugLog("Failed to normalize video URI: \(uri)")
            }
        }
        
        return nil
    }
    
    /// Validates that the asset contains at least one video track.
    /// Prevents silent failures when a broken URL/path produces an empty AVAsset.
    private static func hasVideoTrack(_ asset: AVAsset) async -> Bool {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            return !tracks.isEmpty
        } catch {
            debugLog("Failed to load video tracks: \(error.localizedDescription)")
            return false
        }
    }

    private static func loadAVAsset(from phAsset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { asset, _, _ in
                continuation.resume(returning: asset)
            }
        }
    }

    private static func videoTrimRange(for asset: AVAsset, mediaItem: MediaItem) async -> CMTimeRange? {
        let duration: Double
        do {
            let cmDuration = try await asset.load(.duration)
            duration = cmDuration.seconds.isFinite ? cmDuration.seconds : 0
        } catch {
            return nil
        }

        guard duration > 0 else { return nil }

        // If start/end never set (trimmer didn't callback), still cap at chat max (8 min).
        let maxClip = ChatVideoSendPolicy.maxDurationSeconds
        let start = max(0, mediaItem.video?.startTime ?? 0)
        let defaultEnd = min(duration, start + maxClip)
        let rawEnd = mediaItem.video?.endTime ?? defaultEnd
        let end = min(max(rawEnd, start + 1), duration, start + maxClip)

        guard end > start else { return nil }

        return CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
    }

    private static func composeOverlays(
        videoURL: URL,
        mediaInfo: MediaInfo,
        containerSize: CGSize
    ) async -> EditedMediaResult {
        await withCheckedContinuation { continuation in
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")

            let drawings = mediaInfo.lines.map {
                DrawingLine(
                    points: $0.points,
                    color: UIColor($0.color),
                    lineWidth: $0.lineWidth
                )
            }

            var textOverlays: [TextOverlay] = []
            if !mediaInfo.overLayText.isEmpty {
                let fonts = ConstantFont.shared.AllFonts
                let family = fonts[mediaInfo.selectedFontIndex].family
                let font = UIFont(name: family, size: fontSizeForExport(mediaInfo)) ?? .systemFont(ofSize: 32)
                let center = CGPoint(
                    x: containerSize.width / 2 + mediaInfo.textOffset.width,
                    y: containerSize.height / 2 + mediaInfo.textOffset.height
                )
                textOverlays.append(TextOverlay(
                    text: mediaInfo.overLayText,
                    position: center,
                    font: font,
                    color: UIColor(mediaInfo.selectedTextColor),
                    backgroundColor: nil,
                    scale: mediaInfo.textScale
                ))
            }

            composeVideoWithOverlays(
                videoURL: videoURL,
                drawings: drawings,
                textOverlays: textOverlays,
                screenSize: containerSize,
                outputURL: outputURL
            ) { result in
                switch result {
                case .success(let url):
                    continuation.resume(returning: .exportedVideo(url))
                case .failure:
                    continuation.resume(returning: .exportedVideo(videoURL))
                }
            }
        }
    }

    private static func fontSizeForExport(_ info: MediaInfo) -> CGFloat {
        32 * info.textScale
    }

    private static func fallbackResult(for preview: PreviewMediaItem, useHD: Bool) -> EditedMediaResult {
        switch preview.source {
        case .gallery(let media):
            if media.type == .image, let image = media.highQualityImage {
                let data = ChatImageSendEncoder.encode(image, useHD: useHD)
                return .exportedImage(image, jpegData: data)
            }
            if media.type == .video {
                return .uneditedGallery(media)
            }
            return .uneditedGallery(media)
        case .captured(.image(let image, let data)):
            let encoded = ChatImageSendEncoder.encode(image, useHD: useHD)
            return .exportedImage(image, jpegData: data ?? encoded)
        case .captured(.video(let url)), .captured(.videoNote(let url)):
            return .exportedVideo(url)
        }
    }

    // MARK: - Line compositing

    static func compositeLines(lines: [Line], onto background: UIImage, size: CGSize) -> UIImage {
        guard size.width > 0, size.height > 0 else { return background }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            background.draw(in: CGRect(origin: .zero, size: size))
            for line in lines {
                let path = UIBezierPath()
                guard let first = line.points.first else { continue }
                path.move(to: first)
                for point in line.points.dropFirst() { path.addLine(to: point) }
                UIColor(line.color).setStroke()
                path.lineWidth = line.lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        }
    }
}
