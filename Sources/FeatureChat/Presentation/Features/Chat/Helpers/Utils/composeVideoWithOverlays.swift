//
//  DrawingLine.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//



import AVFoundation
import UIKit
import CoreImage

// MARK: - Models

public struct DrawingLine {
    let points: [CGPoint]
    let color: UIColor
    let lineWidth: CGFloat
}

public struct TextOverlay {
    let text: String
    let position: CGPoint      // Final center position in screen coordinates (already includes offset)
    let font: UIFont
    let color: UIColor
    let backgroundColor: UIColor?
    let scale: CGFloat
}

// MARK: - Main Composer

/// Composes video with drawing and text overlays.
/// - Parameters:
///   - videoURL: Source video URL (already trimmed)
///   - drawings: Drawing lines in screen coordinates
///   - textOverlays: Text overlays in screen coordinates
///   - screenSize: The screen size used when capturing drawings/text
///   - outputURL: Destination URL for the composed video
///   - onProgress: Optional progress callback (0.0 to 1.0)
///   - completion: Result with the output URL or error
public func composeVideoWithOverlays(
    videoURL: URL,
    drawings: [DrawingLine],
    textOverlays: [TextOverlay],
    screenSize: CGSize,
    outputURL: URL,
    onProgress: ((Float) -> Void)? = nil,
    completion: @escaping (Result<URL, Error>) -> Void
) {

    let asset = AVAsset(url: videoURL)

    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        completion(.failure(NSError(domain: "VideoComposer", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "No video track found"])))
        return
    }

    // Compute actual render size accounting for preferredTransform (portrait videos)
    let naturalSize = videoTrack.naturalSize
    let transform = videoTrack.preferredTransform
    let transformedSize = naturalSize.applying(transform)
    let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

    let composition = AVMutableComposition()
    let duration = asset.duration

    guard let compVideoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
        completion(.failure(NSError(domain: "VideoComposer", code: 2)))
        return
    }

    do {
        try compVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
    } catch {
        completion(.failure(error))
        return
    }

    // Copy audio track
    if let audioTrack = asset.tracks(withMediaType: .audio).first,
       let compAudioTrack = composition.addMutableTrack(
           withMediaType: .audio,
           preferredTrackID: kCMPersistentTrackID_Invalid
       ) {
        try? compAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: audioTrack,
            at: .zero
        )
    }

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    videoComposition.customVideoCompositorClass = OverlayCompositor.self

    let instruction = OverlayInstruction(
        trackID: compVideoTrack.trackID,
        timeRange: CMTimeRange(start: .zero, duration: duration),
        transform: transform,
        renderSize: renderSize,
        drawings: drawings,
        textOverlays: textOverlays,
        screenSize: screenSize
    )

    videoComposition.instructions = [instruction]

    // Use a capped quality preset — HighestQuality re-encodes at max bitrate
    guard let exporter = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPreset1920x1080
    ) else {
        completion(.failure(NSError(domain: "VideoComposer", code: 3)))
        return
    }

    try? FileManager.default.removeItem(at: outputURL)
    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4
    exporter.videoComposition = videoComposition

    // Start progress polling
    if let onProgress = onProgress {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            let progress = exporter.progress
            onProgress(progress)
            if progress >= 1.0 || exporter.status != .exporting {
                timer.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    exporter.exportAsynchronously {
        DispatchQueue.main.async {
            onProgress?(1.0)
            switch exporter.status {
            case .completed:
                completion(.success(outputURL))
            default:
                completion(.failure(exporter.error ?? NSError(domain: "VideoComposer", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Export failed with status: \(exporter.status.rawValue)"])))
            }
        }
    }
}

// MARK: - Instruction
 final class OverlayInstruction: NSObject, AVVideoCompositionInstructionProtocol {

    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let renderSize: CGSize
    let drawings: [DrawingLine]
    let textOverlays: [TextOverlay]
    let screenSize: CGSize

    var timeRange: CMTimeRange
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    var containsTweening = false
    var enablePostProcessing = false

    init(
        trackID: CMPersistentTrackID,
        timeRange: CMTimeRange,
        transform: CGAffineTransform,
        renderSize: CGSize,
        drawings: [DrawingLine],
        textOverlays: [TextOverlay],
        screenSize: CGSize
    ) {
        self.trackID = trackID
        self.timeRange = timeRange
        self.transform = transform
        self.renderSize = renderSize
        self.drawings = drawings
        self.textOverlays = textOverlays
        self.screenSize = screenSize
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

// MARK: - Custom Compositor (Optimized)

 final class OverlayCompositor: NSObject, AVVideoCompositing {

    var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    private let queue = DispatchQueue(label: "overlay.render.queue")
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    /// Cached pre-rendered overlay (since drawings/text are static for the entire video)
    private var cachedOverlay: CIImage?
    private var overlayRendered = false

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Invalidate cache when render context changes
        cachedOverlay = nil
        overlayRendered = false
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {

        queue.async {

            guard
                let instruction = request.videoCompositionInstruction as? OverlayInstruction,
                let sourceBuffer = request.sourceFrame(byTrackID: instruction.trackID),
                let outputBuffer = request.renderContext.newPixelBuffer()
            else {
                request.finish(with: NSError(domain: "RenderError", code: 1))
                return
            }

            var image = CIImage(cvPixelBuffer: sourceBuffer)
            image = image.transformed(by: instruction.transform)

            // Pre-render overlay once and cache it
            if !self.overlayRendered {
                self.cachedOverlay = self.renderStaticOverlay(
                    renderSize: instruction.renderSize,
                    screenSize: instruction.screenSize,
                    drawings: instruction.drawings,
                    texts: instruction.textOverlays
                )
                self.overlayRendered = true
            }

            if let overlay = self.cachedOverlay {
                image = overlay.composited(over: image)
            }

            self.ciContext.render(image, to: outputBuffer)
            request.finish(withComposedVideoFrame: outputBuffer)
        }
    }

    // MARK: - Pre-render static overlay (called once, not per frame)

    private func renderStaticOverlay(
        renderSize: CGSize,
        screenSize: CGSize,
        drawings: [DrawingLine],
        texts: [TextOverlay]
    ) -> CIImage? {
        
        guard !drawings.isEmpty || !texts.isEmpty else { return nil }

        // Scale factors from screen coordinates to video coordinates
        let scaleX = renderSize.width / max(screenSize.width, 1)
        let scaleY = renderSize.height / max(screenSize.height, 1)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)

        let img = renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext
            ctx.clear(CGRect(origin: .zero, size: renderSize))

            // Draw lines (scaled from screen space to video space)
            for d in drawings {
                guard let first = d.points.first else { continue }
                ctx.setStrokeColor(d.color.cgColor)
                ctx.setLineWidth(d.lineWidth * max(scaleX, scaleY))
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.move(to: CGPoint(x: first.x * scaleX, y: first.y * scaleY))
                for pt in d.points.dropFirst() {
                    ctx.addLine(to: CGPoint(x: pt.x * scaleX, y: pt.y * scaleY))
                }
                ctx.strokePath()
            }

            // Draw text overlays (scaled from screen space to video space)
            for t in texts {
                // Scale font size proportionally
                let scaledFontSize = t.font.pointSize * max(scaleX, scaleY)
                let scaledFont = t.font.withSize(scaledFontSize)
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: scaledFont,
                    .foregroundColor: t.color
                ]

                let textSize = (t.text as NSString).size(withAttributes: attrs)
                let hp: CGFloat = 12 * scaleX
                let vp: CGFloat = 8 * scaleY

                // position already contains the final screen-space center (including offset)
                let center = CGPoint(
                    x: t.position.x * scaleX,
                    y: t.position.y * scaleY
                )

                let bgRect = CGRect(
                    x: center.x - (textSize.width + hp * 2) / 2,
                    y: center.y - (textSize.height + vp * 2) / 2,
                    width: textSize.width + hp * 2,
                    height: textSize.height + vp * 2
                )

                ctx.saveGState()
                ctx.translateBy(x: center.x, y: center.y)
                ctx.scaleBy(x: t.scale, y: t.scale)
                ctx.translateBy(x: -center.x, y: -center.y)

                if let bg = t.backgroundColor {
                    ctx.setFillColor(bg.cgColor)
                    let path = UIBezierPath(roundedRect: bgRect, cornerRadius: 8 * max(scaleX, scaleY))
                    ctx.addPath(path.cgPath)
                    ctx.fillPath()
                }

                let textRect = CGRect(
                    x: center.x - textSize.width / 2,
                    y: center.y - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )

                (t.text as NSString).draw(in: textRect, withAttributes: attrs)
                ctx.restoreGState()
            }
        }

        guard let cg = img.cgImage else { return nil }
        return CIImage(cgImage: cg)
    }
}
