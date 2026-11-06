//
//  CallPictureInPictureController.swift
//  FeatureChat
//
//  System Picture-in-Picture for an active call — audio or video.
//
//  Uses the video-call flavour of PiP (`AVPictureInPictureVideoCallViewController`),
//  which is the API Apple reserves for calls: it survives leaving the app, so the
//  floating window follows the user to the home screen and into other apps —
//  unlike the media flavour, which is tied to an AVPlayer.
//
//  It shows the *remote* side of the call, never the local camera: seeing who
//  you are talking to is what the window is for, during a screen share the local
//  camera is deliberately paused, and rendering only remote tracks removes the
//  need for the `com.apple.developer.avfoundation.multitasking-camera-access`
//  entitlement, which exists to keep the *camera* alive in multitasking.
//
//  What goes in the window is `CallPiPStageContent` — the call's own stage. This
//  controller only owns the window itself: when it opens, when it closes, and
//  what the app should do when the user taps restore.
//
//  Wiring it up needs two things beyond this file:
//    1. `voip` + `audio` in UIBackgroundModes (call keeps running backgrounded).
//    2. A source UIView that is live in the window hierarchy —
//       `CallPictureInPictureHost` mounts one above the call screen.
//
//  PiP for video calls does not work in the Simulator; it needs a real device.
//

import AVKit
import Combine
import SwiftUI
import UIKit
import WaanguCoreKit

// MARK: - PiP content

/// Hosts the call inside the floating window.
///
/// One view for the whole call rather than a `UIView` swapped per track:
/// `CallPiPStageContent` observes the call itself and re-lays itself out as
/// people join, leave, turn a camera on or start sharing — the same way the
/// call screen does. Pushing a single track in here is what made the window
/// show one participant out of a group.
final class CallPiPContentViewController: AVPictureInPictureVideoCallViewController {

    /// Hosted as a child so the SwiftUI inside receives appearance callbacks and
    /// keeps updating; a bare `view` would render once and stop.
    private let stageHost = UIHostingController(rootView: CallPiPStageContent())

    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)
        // Portrait tile matching a phone video feed.
        preferredContentSize = CGSize(width: 1080, height: 1920)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(stageHost)
        pin(stageHost.view)
        stageHost.didMove(toParent: self)
    }

    private func pin(_ subview: UIView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: view.topAnchor),
            subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}

// MARK: - Controller

@MainActor
final class CallPictureInPictureController: NSObject, ObservableObject {

    @Published private(set) var isActive = false

    /// Start requested, nothing heard back yet.
    ///
    /// The window takes a moment to appear, and whoever is deciding whether to
    /// show fallback chrome instead needs to know the difference between "PiP is
    /// coming" and "PiP is not going to happen" — otherwise the fallback flashes
    /// on screen for that moment and then disappears again.
    @Published private(set) var isStarting = false

    @Published private(set) var isSupported = AVPictureInPictureController.isPictureInPictureSupported()

    /// The user tapped the window's restore control. The call UI should come
    /// back to full screen; a closure rather than a direct `VoipManager` call so
    /// this stays a plain AVKit wrapper.
    var onRestoreUserInterface: (() -> Void)?

    private var controller: AVPictureInPictureController?
    private var contentViewController: CallPiPContentViewController?

    /// Whether a window is on screen or on its way.
    var isRunningOrStarting: Bool { isActive || isStarting }

    /// Binds PiP to a live source view. Safe to call again when the view is
    /// recreated. No capture session: the window shows the remote participant,
    /// so an audio call can use it too by supplying any live anchor view.
    func attach(sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isSupported = false
            return
        }

        // Nothing to do if we are already driving this exact source view.
        if let existing = controller,
           existing.contentSource?.activeVideoCallSourceView === sourceView {
            return
        }

        let content = contentViewController ?? CallPiPContentViewController(
            nibName: nil,
            bundle: nil
        )
        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: content
        )

        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        // Hands off to PiP automatically when the user leaves the app mid-call.
        pip.canStartPictureInPictureAutomaticallyFromInline = true

        self.contentViewController = content
        self.controller = pip
    }

    /// Asks for the floating window.
    ///
    /// Reports back whether the request could even be made: with no controller
    /// (nothing attached) or no PiP support on this device — the Simulator, for
    /// one — there will never be a window, and the caller needs to know that now
    /// rather than waiting for a delegate callback that is not coming.
    @discardableResult
    func start() -> Bool {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isSupported = false
            return false
        }
        guard let controller else { return false }
        guard !controller.isPictureInPictureActive else { return true }

        isStarting = true
        controller.startPictureInPicture()
        return true
    }

    func stop() {
        isStarting = false
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    /// Tears the controller down when the call ends so no stale source view is retained.
    ///
    /// `attach` rebuilds from scratch afterwards, so a later call gets a working
    /// window again — this must not be the thing that kills PiP for the rest of
    /// the app session.
    func detach() {
        stop()
        controller?.delegate = nil
        controller = nil
        contentViewController = nil
        isActive = false
        isStarting = false
    }
}

// MARK: - AVPictureInPictureControllerDelegate

// AVKit declares these delegate callbacks without actor annotations, but it only
// ever invokes them on the main thread. @preconcurrency records that guarantee so
// the @MainActor isolation above stays intact under Swift 6.
extension CallPictureInPictureController: @preconcurrency AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isStarting = false
        isActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isStarting = false
        isActive = false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        isStarting = false
        isActive = false
        NSLog("[CallPiP] Failed to start: \(error.localizedDescription)")
    }

    /// The window's restore control. Bring the call screen back before telling
    /// AVKit the interface is ready, so the window does not dismiss onto a UI
    /// that has not been restored yet.
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
            @escaping (Bool) -> Void
    ) {
        onRestoreUserInterface?()
        completionHandler(true)
    }
}
