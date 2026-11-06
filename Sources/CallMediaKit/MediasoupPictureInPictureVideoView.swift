//
//  MediasoupPictureInPictureVideoView.swift
//  CallMediaKit
//
//  A video surface for Picture-in-Picture.
//
//  `RTCMTLVideoView` cannot serve here. It renders through Metal, and iOS
//  suspends Metal work for a backgrounded app — so the PiP window would hold
//  whatever frame was drawn last, at exactly the moment it is the only thing the
//  user can see. That is the frozen-tile bug.
//
//  `AVSampleBufferDisplayLayer` is composited by the system rather than by the
//  app, so it keeps updating while the app is suspended. It is also what AVKit
//  expects PiP content to be built on.
//
//  Only used for PiP. Inline video stays on the Metal view, which is cheaper and
//  entirely correct in the foreground.
//

#if canImport(UIKit)
import UIKit
import AVFoundation
import WaanguCoreKit
import WebRTC

final class MediasoupPictureInPictureVideoView: UIView {

    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    private var displayLayer: AVSampleBufferDisplayLayer {
        // Safe: `layerClass` above guarantees the type.
        layer as! AVSampleBufferDisplayLayer
    }

    /// Held so the renderer can be detached when this view goes away; leaving it
    /// attached keeps the view alive for the lifetime of the track.
    private weak var track: RTCVideoTrack?

    init(track: RTCVideoTrack) {
        self.track = track
        super.init(frame: .zero)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspectFill
        track.add(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // `remove` is safe from any thread and must happen, or WebRTC keeps
        // delivering frames into a dead renderer.
        track?.remove(self)
    }
}

// MARK: - RTCVideoRenderer

extension MediasoupPictureInPictureVideoView: RTCVideoRenderer {

    func setSize(_ size: CGSize) {
        // The layer follows its own bounds; nothing to do. Required by protocol.
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }

        // Only CVPixelBuffer-backed frames can be shown without a conversion
        // pass. Remote WebRTC frames are I420 buffers, so they are converted to
        // NV12 in a CVPixelBuffer first.
        guard let pixelBuffer = Self.pixelBuffer(from: frame) else { return }
        guard let sampleBuffer = Self.sampleBuffer(
            from: pixelBuffer,
            rotation: frame.rotation,
            timeStampNs: frame.timeStampNs
        ) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // A failed layer stops accepting buffers permanently until flushed.
            if self.displayLayer.status == .failed {
                self.displayLayer.flush()
            }
            self.displayLayer.enqueue(sampleBuffer)
        }
    }

    // MARK: - Frame conversion

    private static func pixelBuffer(from frame: RTCVideoFrame) -> CVPixelBuffer? {
        if let native = frame.buffer as? RTCCVPixelBuffer {
            return native.pixelBuffer
        }

        // Remote frames arrive as I420. `toI420()` is a no-op when they already
        // are, and gives a uniform source for the NV12 conversion below.
        let i420 = frame.buffer.toI420()
        return makeNV12PixelBuffer(from: i420)
    }

    /// I420 (three planes) → NV12 (luma + interleaved chroma), which is what
    /// `AVSampleBufferDisplayLayer` accepts.
    private static func makeNV12PixelBuffer(
        from buffer: RTCI420BufferProtocol
    ) -> CVPixelBuffer? {
        let width = Int(buffer.width)
        let height = Int(buffer.height)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let output = pixelBuffer else { return nil }

        guard CVPixelBufferLockBaseAddress(output, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        // Luma: straight copy, row by row, because the destination is padded.
        if let lumaBase = CVPixelBufferGetBaseAddressOfPlane(output, 0) {
            let destination = lumaBase.assumingMemoryBound(to: UInt8.self)
            let destinationStride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
            let sourceStride = Int(buffer.strideY)
            for row in 0..<height {
                memcpy(
                    destination + row * destinationStride,
                    buffer.dataY + row * sourceStride,
                    width
                )
            }
        }

        // Chroma: U and V are separate planes in I420 and interleaved in NV12,
        // so they are woven together rather than copied.
        if let chromaBase = CVPixelBufferGetBaseAddressOfPlane(output, 1) {
            let destination = chromaBase.assumingMemoryBound(to: UInt8.self)
            let destinationStride = CVPixelBufferGetBytesPerRowOfPlane(output, 1)
            let chromaWidth = width / 2
            let chromaHeight = height / 2
            let strideU = Int(buffer.strideU)
            let strideV = Int(buffer.strideV)

            for row in 0..<chromaHeight {
                let rowStart = destination + row * destinationStride
                let sourceU = buffer.dataU + row * strideU
                let sourceV = buffer.dataV + row * strideV
                for column in 0..<chromaWidth {
                    rowStart[column * 2] = sourceU[column]
                    rowStart[column * 2 + 1] = sourceV[column]
                }
            }
        }

        return output
    }

    private static func sampleBuffer(
        from pixelBuffer: CVPixelBuffer,
        rotation: RTCVideoRotation,
        timeStampNs: Int64
    ) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: timeStampNs, timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return nil }

        // Display immediately rather than scheduling against a clock the layer
        // does not have — PiP is live video, not timed playback.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: true
        ) {
            let first = unsafeBitCast(
                CFArrayGetValueAtIndex(attachments, 0),
                to: CFMutableDictionary.self
            )
            CFDictionarySetValue(
                first,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        return sampleBuffer
    }
}
#endif
