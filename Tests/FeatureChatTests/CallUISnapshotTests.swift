//
//  CallUISnapshotTests.swift
//  FeatureChatTests
//
//  Renders each call surface into a real UIWindow on the simulator and writes a
//  PNG per state, so the call UI can be reviewed without logging into the app.
//
//  A real window (rather than SwiftUI's `ImageRenderer`) is used deliberately:
//  it goes through the render server, so `.ultraThinMaterial`, blur and
//  `drawingGroup()` rasterise the way they do in the running app.
//
//  Run:
//    xcodebuild test -scheme FeatureChat \
//      -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
//      -only-testing:FeatureChatTests/CallUISnapshotTests
//
//  Each test prints an absolute host path to its PNG.
//

import XCTest
import SwiftUI
@testable import WaanguFeatureChat

@MainActor
final class CallUISnapshotTests: XCTestCase {

    // iPhone 16 Pro logical size and safe-area insets.
    private let canvasSize = CGSize(width: 402, height: 874)
    private let notchInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

    private let callerName = "My Onamob Number"

    // MARK: - Incoming

    func testIncomingAudioCall() throws {
        configureVoip(phase: .incomingRinging(handle: callerName, isVideo: false), isVideo: false)

        let view = IncomingCallView(
            callerName: callerName,
            callerImage: nil,
            isVideo: false
        )

        try snapshot(view, named: "01-incoming-audio")
    }

    func testIncomingVideoCall() throws {
        configureVoip(phase: .incomingRinging(handle: callerName, isVideo: true), isVideo: true)

        let view = IncomingCallView(
            callerName: callerName,
            callerImage: nil,
            isVideo: true
        )

        try snapshot(view, named: "05-incoming-video")
    }

    // MARK: - Connected audio

    func testConnectedAudioCall() throws {
        configureVoip(
            phase: .connected(isVideo: false),
            isVideo: false,
            duration: 8,
            isMuted: true,
            isOnSpeaker: true
        )

        let view = AudioCallConnectedView(
            callerName: callerName,
            callerImage: nil
        )

        try snapshot(view, named: "02-audio-connected")
    }

    // MARK: - Connected video

    func testConnectedVideoCallWithControls() throws {
        configureVoip(
            phase: .connected(isVideo: true),
            isVideo: true,
            duration: 58,
            isMuted: true,
            isOnSpeaker: true
        )

        let view = VideoCallView(
            callerName: callerName,
            callerImage: nil
        )

        try snapshot(view, named: "03-video-controls-visible")
    }

    /// The chrome auto-hides after four idle seconds; wait it out, then capture.
    func testConnectedVideoCallChromeHidden() throws {
        configureVoip(
            phase: .connected(isVideo: true),
            isVideo: true,
            duration: 58,
            isMuted: true,
            isOnSpeaker: true
        )

        let view = VideoCallView(
            callerName: callerName,
            callerImage: nil
        )

        try snapshot(view, named: "04-video-chrome-hidden", settleFor: 5.0)
    }

    // MARK: - Harness

    /// Drives the shared VoIP singleton into the state the views observe.
    private func configureVoip(
        phase: CallPhase,
        isVideo: Bool,
        duration: Int = 0,
        isMuted: Bool = false,
        isOnSpeaker: Bool = false
    ) {
        let voip = VoipManager.shared
        voip.callerName = callerName
        voip.callHandle = "+000000000"
        voip.callerProfileImage = nil
        voip.hasVideo = isVideo
        voip.callDuration = duration
        voip.isMuted = isMuted
        voip.isOnSpeaker = isOnSpeaker
        voip.callPhase = phase
    }

    /// Hosts `view` in a real window, lets it settle, and writes a PNG.
    private func snapshot<V: View>(
        _ view: V,
        named name: String,
        settleFor settle: TimeInterval = 1.2
    ) throws {
        let host = UIHostingController(rootView: view)
        host.additionalSafeAreaInsets = notchInsets
        host.view.frame = CGRect(origin: .zero, size: canvasSize)
        host.overrideUserInterfaceStyle = .dark

        let window = makeWindow()
        window.rootViewController = host
        window.makeKeyAndVisible()

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Let async image loads, transitions and auto-hide timers land.
        let deadline = Date().addingTimeInterval(settle)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { _ in
            // drawHierarchy goes through the render server, so materials and
            // drawingGroup() layers rasterise correctly.
            window.drawHierarchy(in: CGRect(origin: .zero, size: canvasSize), afterScreenUpdates: true)
        }

        let data = try XCTUnwrap(image.pngData(), "Failed to encode PNG for \(name)")
        let url = Self.outputDirectory.appendingPathComponent("\(name).png")
        try data.write(to: url)

        print("📸 SNAPSHOT \(name): \(url.path)")

        window.isHidden = true
    }

    private func makeWindow() -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(origin: .zero, size: canvasSize)
        window.overrideUserInterfaceStyle = .dark
        return window
    }

    /// Simulator temp dirs are real host paths, so the PNGs are readable from the Mac.
    private static let outputDirectory: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CallUISnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
