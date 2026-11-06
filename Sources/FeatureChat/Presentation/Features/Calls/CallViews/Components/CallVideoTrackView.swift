//
//  CallVideoTrackView.swift
//  FeatureChat
//
//  Renders a call video track. The view itself is built by CallMediaKit through
//  `CallVideoRendererFactoryProtocol`, so this file — and the whole feature —
//  never imports WebRTC.
//

import SwiftUI
import WaanguCoreKit

/// Where the app target registers the renderer. It cannot travel in
/// `ChatDependencies` because building views is main-actor work and the
/// dependency container is `Sendable`.
@MainActor
public enum CallVideoRendering {
    public static var factory: (any CallVideoRendererFactoryProtocol)?
}

/// Which surface a track should be drawn on.
///
/// The two are not interchangeable. Inline is Metal-backed: faster, and correct
/// for anything on screen while the app is in the foreground. The
/// Picture-in-Picture surface is composited by the system, which is the only way
/// it keeps producing frames once the app is backgrounded — the moment the PiP
/// window is the only thing the user can see.
enum CallVideoRenderingMode {
    case inline
    case pictureInPicture
}

extension EnvironmentValues {
    /// Set once at the root of a stage; every tile inside it follows.
    var callVideoRenderingMode: CallVideoRenderingMode {
        get { self[CallVideoRenderingModeKey.self] }
        set { self[CallVideoRenderingModeKey.self] = newValue }
    }
}

private struct CallVideoRenderingModeKey: EnvironmentKey {
    static let defaultValue: CallVideoRenderingMode = .inline
}

/// Shows one track. Renders nothing when no renderer has been registered, which
/// is the case in tests and previews.
struct CallVideoTrackView: UIViewRepresentable {

    let track: any CallVideoTrackProtocol
    /// True for the local front camera, which reads as a mirror.
    var isMirrored: Bool = false
    var fillsBounds: Bool = true

    @Environment(\.callVideoRenderingMode) private var renderingMode

    func makeUIView(context: Context) -> UIView {
        guard let factory = CallVideoRendering.factory else { return UIView() }

        // Mirroring and content mode are inline concerns: the PiP surface is
        // built for one job and takes no options.
        guard renderingMode == .inline else {
            return factory.makePictureInPictureView(for: track)
        }

        return factory.makeVideoView(
            for: track,
            mirrored: isMirrored,
            fillsBounds: fillsBounds
        )
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // The renderer is bound to its track for its whole life; a different
        // track produces a different view through `id(_:)` at the call site.
    }
}
