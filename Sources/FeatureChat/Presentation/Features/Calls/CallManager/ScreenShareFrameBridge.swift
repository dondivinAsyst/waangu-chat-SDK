//
//  ScreenShareFrameBridge.swift
//  FeatureChat
//
//  Owns the receiving half of the App Group socket and pushes each frame into
//  the media engine's screen source. Lifecycle and frames arrive on separate
//  channels, so this deliberately tolerates frames before start and after stop.
//

import Foundation
import CoreVideo
import WaanguScreenShareTransport

final class ScreenShareFrameBridge {

    /// A closure rather than the whole engine protocol: the bridge needs exactly
    /// one method, and depending on the full protocol would force every test to
    /// stub twenty unrelated ones.
    typealias FrameSink = (CVPixelBuffer, Int, UInt64) async -> Void

    /// Fires on the first frame of a broadcast. The system picker gives no
    /// completion callback, so this is the only reliable evidence that the user
    /// actually started sharing rather than dismissing the sheet.
    var onFirstFrame: (() -> Void)?

    private let resolveSocketPath: () throws -> String
    private let submitFrame: FrameSink
    private var receiver: ScreenFrameReceiver?
    private var hasSeenFrame = false
    private let lock = NSLock()

    init(
        resolveSocketPath: @escaping () throws -> String = { try ScreenShareSocketPath.resolve() },
        submitFrame: @escaping FrameSink
    ) {
        self.resolveSocketPath = resolveSocketPath
        self.submitFrame = submitFrame
    }

    func start() throws {
        lock.lock()
        let alreadyRunning = receiver != nil
        lock.unlock()
        guard !alreadyRunning else { return }

        let path = try resolveSocketPath()
        let receiver = ScreenFrameReceiver(socketPath: path)
        try receiver.start { [weak self] header, pixelBuffer in
            self?.ingest(header: header, pixelBuffer: pixelBuffer)
        }

        lock.lock()
        self.receiver = receiver
        hasSeenFrame = false
        lock.unlock()

        NSLog("[ScreenShare] APP listening on \(path)")
    }

    func stop() {
        lock.lock()
        let receiver = self.receiver
        self.receiver = nil
        hasSeenFrame = false
        lock.unlock()

        receiver?.stop()
    }

    private func ingest(header: ScreenFrameHeader, pixelBuffer: CVPixelBuffer) {
        lock.lock()
        let isFirst = !hasSeenFrame
        if isFirst { hasSeenFrame = true }
        lock.unlock()

        if isFirst {
            NSLog(
                "[ScreenShare] APP first frame received "
                + "\(header.width)x\(header.height) rot=\(header.rotation.degrees)°"
            )
            onFirstFrame?()
        }

        Task { [submitFrame] in
            await submitFrame(
                pixelBuffer,
                header.rotation.degrees,
                header.timestampNanos
            )
        }
    }
}
