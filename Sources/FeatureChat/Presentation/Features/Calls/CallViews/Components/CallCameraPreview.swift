//
//  CallCameraPreview.swift
//  FeatureChat
//
//  Renders an AVCaptureSession into SwiftUI.
//
//  A capture session can feed several preview layers at once, which is what
//  makes the inline self-view and the Picture-in-Picture window able to show the
//  same camera simultaneously.
//
//  `onViewCreated` hands the backing UIView up to the caller so it can be
//  registered as the PiP content source — AVKit needs a real UIView, not a
//  SwiftUI view.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - UIView

/// UIView whose layer *is* the capture preview layer.
final class CameraPreviewUIView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // Safe: `layerClass` above guarantees the type.
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("CameraPreviewUIView layer must be AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    init(session: AVCaptureSession?) {
        super.init(frame: .zero)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        if let session {
            previewLayer.session = session
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(session: AVCaptureSession) {
        guard previewLayer.session !== session else { return }
        previewLayer.session = session
    }
}

// MARK: - SwiftUI bridge

struct CallCameraPreview: UIViewRepresentable {

    let session: AVCaptureSession
    /// Mirrors the front camera so the self-view reads like a mirror.
    var isMirrored: Bool = true
    var onViewCreated: (UIView) -> Void = { _ in }

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView(session: session)
        applyMirroring(to: view)
        onViewCreated(view)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.attach(session: session)
        applyMirroring(to: uiView)
    }

    private func applyMirroring(to view: CameraPreviewUIView) {
        guard let connection = view.previewLayer.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirrored
    }
}
