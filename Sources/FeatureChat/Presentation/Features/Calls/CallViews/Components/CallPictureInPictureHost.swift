//
//  CallPictureInPictureHost.swift
//  FeatureChat
//
//  Keeps Picture-in-Picture alive above the call screen.
//
//  PiP used to be owned by `VideoCallView`, which is exactly the view minimising
//  tears down — so the controller died at the moment the window was wanted, and
//  the only thing that ever started it was AVKit's automatic hand-off when the
//  whole app went to background. Minimising inside the app could never produce a
//  window.
//
//  So the anchor and the controller live here instead, mounted for as long as
//  the chat shell is: minimise starts the window, restoring stops it, and the
//  call screen underneath is free to come and go.
//
//  PiP for video calls does not run in the Simulator. `start()` says so straight
//  away, which is what lets the caller fall back to the banner rather than
//  minimising a call into nothing.
//

import SwiftUI
import UIKit

struct CallPictureInPictureHost: View {

    @ObservedObject var pip: CallPictureInPictureController
    @ObservedObject private var voip = VoipManager.shared

    /// Held so the controller can be rebuilt after a call ends — `attach` only
    /// hears about the view once, when it is created.
    @State private var anchorView: UIView?

    var body: some View {
        CallPiPAnchorView { view in
            anchorView = view
            pip.onRestoreUserInterface = { VoipManager.shared.expand() }
            attachIfLive()
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .onChange(of: voip.callPhase) { _, phase in
            if phase.isActive {
                attachIfLive()
            } else {
                // Between calls: release the renderer and the source view, but
                // leave the anchor mounted so the next call can re-attach.
                pip.detach()
            }
        }
        .onChange(of: voip.isMinimized) { _, isMinimized in
            syncWindow(isMinimized: isMinimized)
        }
        // A call that becomes video while already minimised — the far end
        // upgrading — earns the window it did not qualify for a moment ago.
        .onChange(of: voip.isVideoCall) { _, _ in
            syncWindow(isMinimized: voip.isMinimized)
        }
        // Nothing here feeds the window its content: `CallPiPStageContent`
        // observes the call itself and follows people joining, leaving and
        // turning cameras on without being pushed anything.
    }

    /// Binds the controller to the anchor once there is a call to show.
    @MainActor
    private func attachIfLive() {
        guard let anchorView, voip.callPhase.isActive else { return }
        pip.attach(sourceView: anchorView)
        // Minimised before the anchor was ready — start now rather than waiting
        // for a state change that has already happened.
        syncWindow(isMinimized: voip.isMinimized)
    }

    /// The window follows `isMinimized`, for video calls only.
    @MainActor
    private func syncWindow(isMinimized: Bool) {
        guard isMinimized, voip.minimizesToPictureInPicture else {
            pip.stop()
            return
        }
        pip.start()
    }
}
