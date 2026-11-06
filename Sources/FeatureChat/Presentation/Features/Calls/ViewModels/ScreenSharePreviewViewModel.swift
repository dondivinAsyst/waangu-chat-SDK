//
//  ScreenSharePreviewViewModel.swift
//  FeatureChat
//
//  Spike scaffolding: proves extension → socket → app frame delivery by drawing
//  the frames. Plan 2 replaces the CGImage conversion with an RTCVideoSource
//  feed, which avoids this per-frame rasterisation entirely.
//

import Foundation
import CoreVideo
import CoreImage
import SwiftUI
import WaanguScreenShareTransport

@MainActor
final class ScreenSharePreviewViewModel: ObservableObject {

    @Published private(set) var latestFrame: CGImage?
    @Published private(set) var stats: String = "idle"

    private var receiver: ScreenFrameReceiver?
    private let context = CIContext()
    private var frameCount = 0
    private var firstFrameDate: Date?

    func start() {
        guard receiver == nil else { return }
        do {
            let path = try ScreenShareSocketPath.resolve()
            let receiver = ScreenFrameReceiver(socketPath: path)
            try receiver.start { [weak self] header, pixelBuffer in
                Task { @MainActor in
                    self?.ingest(header: header, pixelBuffer: pixelBuffer)
                }
            }
            self.receiver = receiver
            stats = "listening"
        } catch {
            stats = "failed to start: \(error)"
        }
    }

    func stop() {
        receiver?.stop()
        receiver = nil
        frameCount = 0
        firstFrameDate = nil
        stats = "idle"
    }

    private func ingest(header: ScreenFrameHeader, pixelBuffer: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        latestFrame = context.createCGImage(image, from: image.extent)

        frameCount += 1
        if firstFrameDate == nil { firstFrameDate = Date() }
        let elapsed = max(Date().timeIntervalSince(firstFrameDate ?? Date()), 0.001)
        let fps = Double(frameCount) / elapsed
        stats = String(
            format: "%dx%d rot %d — %d frames, %.1f fps",
            header.width, header.height, header.rotation.degrees, frameCount, fps
        )
    }
}
