//
//  VoipManager+ScreenShare.swift
//  FeatureChat
//
//  Screen share lifecycle. The media and transport pieces live in CallMediaKit
//  and ScreenShareTransport; this is the part that knows about the call.
//

import Foundation
import WaanguCoreKit
import WaanguScreenShareTransport

/// Remembers whether the camera was on before a share so it is restored only if
/// the user actually had it on.
struct ScreenShareCameraState {
    private(set) var shouldRestoreCamera = false

    mutating func remember(wasCameraOn: Bool) { shouldRestoreCamera = wasCameraOn }
    mutating func clear() { shouldRestoreCamera = false }
}

extension VoipManager {

    /// Matches the already-sharing rejection.
    ///
    /// CALL-INTEGRATION.md §9.3 (:700-717) documents this one as a *(message
    /// libre)* — it has no `code`, so it can only be matched on text. Switching
    /// on `code` here would silently never fire.
    static func isAlreadySharingError(code: String?, message: String?) -> Bool {
        guard let message else { return false }
        return message.lowercased().contains("already sharing screen")
    }

    /// Entry point for "I want to share my screen".
    ///
    /// Order matters: the call switches to video *first* and only asks about
    /// broadcasting once the camera is actually producing. Asking first and
    /// doing both on one tap meant the user confirmed a broadcast while the
    /// video call did not yet exist to carry it.
    ///
    /// A call already in video skips straight to the broadcast confirmation.
    func requestScreenShareSwitch() {
        guard !isSharingScreen else { return }

        if hasVideo {
            pendingVideoSwitch = .shareScreen
            return
        }

        // Switch to video now; the confirmation follows when it is ready.
        isAwaitingVideoForShare = true
        toggleVideo()
    }

    /// Called once the local camera is genuinely producing, to raise the
    /// broadcast confirmation that was deferred by `requestScreenShareSwitch`.
    @MainActor
    func videoBecameReadyForPendingShare() {
        guard isAwaitingVideoForShare else { return }
        isAwaitingVideoForShare = false
        guard !isSharingScreen else { return }
        pendingVideoSwitch = .shareScreen
    }

    /// Abandons a deferred share when the camera never came up — otherwise the
    /// broadcast confirmation would appear later, out of context.
    @MainActor
    func cancelPendingShareSwitch() {
        isAwaitingVideoForShare = false
    }

    // MARK: - Bridge lifecycle

    /// Starts listening for relayed frames. Called when the room is established,
    /// not when the user taps Share: the system picker has no completion
    /// callback, so the first frame is the only reliable "broadcast started"
    /// signal — and it can arrive before we would otherwise be listening.
    func startScreenShareBridge() {
        guard screenFrameBridge == nil, let engine = mediaEngine else { return }

        let bridge = ScreenShareFrameBridge(
            submitFrame: { pixelBuffer, rotation, timestamp in
                await engine.submitScreenFrame(
                    pixelBuffer,
                    rotation: rotation,
                    timestampNanos: timestamp
                )
            }
        )
        bridge.onFirstFrame = { [weak self] in
            Task { @MainActor in await self?.beginScreenShare() }
        }

        do {
            try bridge.start()
            screenFrameBridge = bridge
            screenShareUnavailableReason = nil
        } catch {
            // The call itself is unaffected, so this must not interrupt anything
            // now — but it must not vanish either. Swallowing it silently means
            // the user taps Share, sits through the countdown, and sees nothing
            // happen with no way to find out why. Recorded here, surfaced when
            // they actually try to share.
            // The user gets a plain "unavailable"; the diagnosis goes to the log.
            // `.appGroupUnavailable` means the *app* lacks the App Group
            // entitlement — not the extension — which is a confusing failure
            // from outside, because the extension looks like the culprit.
            screenShareUnavailableReason = ChatTranslationKeys.CALLS_SHARE_SCREEN_UNAVAILABLE
            NSLog("[ScreenShare] bridge unavailable: \(error)")
        }
    }

    func stopScreenShareBridge() {
        screenFrameBridge?.stop()
        screenFrameBridge = nil
    }

    // MARK: - Share lifecycle

    /// Invoked once the extension's first frame lands.
    func beginScreenShare() async {
        guard !isSharingScreen else { return }
        guard let engine = mediaEngine, let room = roomId else {
            await endScreenShare()
            return
        }

        // Load-bearing, not cosmetic: CALL_PRODUCER_STATE addresses producers by
        // {peerId, kind} only (§9.2 :652-664), so two unpaused video producers on
        // one peer would make remote mute state ambiguous. Pausing the camera
        // guarantees at most one unpaused video producer per peer.
        screenShareCameraState.remember(wasCameraOn: hasVideo)
        if hasVideo {
            try? await engine.setCameraEnabled(false)
        }

        do {
            try await engine.startScreenShare()
            NSLog("[ScreenShare] APP screen producer created")
            try await signaling?.sendScreenShareStart(roomId: room)
            NSLog("[ScreenShare] APP published call-screen-share-start room=\(room)")
            isSharingScreen = true
            // The server never echoes this back to us (§9.0 :419), so the
            // sharer's own stage only updates because of this line.
            screenSharingPeerId = getCurrentUserId()
            NSLog("[ScreenShare] APP sharing is live")
        } catch {
            NSLog("[ScreenShare] APP failed to start sharing: \(error)")
            screenShareErrorKey = ChatTranslationKeys.CALLS_SHARE_SCREEN_FAILED
            await endScreenShare()
        }
    }

    func endScreenShare() async {
        // Signal first: the extension is a separate process and should stop
        // sampling the display as early as possible. It is also the only process
        // that can actually end the broadcast.
        BroadcastControlChannel.requestStop()

        let wasSharing = isSharingScreen
        isSharingScreen = false

        await mediaEngine?.stopScreenShare()

        if wasSharing, let room = roomId {
            try? await signaling?.sendScreenShareStop(roomId: room)
        }

        if screenSharingPeerId == getCurrentUserId() { screenSharingPeerId = nil }

        if screenShareCameraState.shouldRestoreCamera {
            try? await mediaEngine?.setCameraEnabled(true)
        }
        screenShareCameraState.clear()
    }

    /// Called from `handleCallError` before the generic failure path.
    ///
    /// Returns true when the error was a rejected screen share, which must *not*
    /// end the call — the generic path calls `finishCall(outcome: .failed)`, and
    /// letting a refused share hang up an otherwise healthy call would be a
    /// serious regression.
    func handleScreenShareRejection(code: String?, message: String?) -> Bool {
        guard Self.isAlreadySharingError(code: code, message: message) else { return false }
        screenShareErrorKey = ChatTranslationKeys.CALLS_SHARE_SCREEN_BUSY
        Task { @MainActor in await endScreenShare() }
        return true
    }
}
