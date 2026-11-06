//
//  ChatCameraPreviewRepresentable.swift
//  FeatureChat
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Session controller (bridges SwiftUI controls ↔ UIKit preview)

@MainActor
final class ChatCameraSessionController: ObservableObject {
    fileprivate weak var previewView: ChatCameraPreviewUIView?

    func capturePhoto() {
        previewView?.capturePhoto()
    }

    func flipCamera() {
        previewView?.flipCamera()
    }

    func startVideoRecording() {
        previewView?.startVideoRecording()
    }

    func stopVideoRecording() {
        previewView?.stopVideoRecording()
    }
}

// MARK: - Capture profile

/// What the session is set up for. Fixed when the preview is created.
enum ChatCameraProfile {
    /// The chat camera: back camera, photos and video, no time limit.
    case standard
    /// A video note: front camera, the microphone recorded with the picture, and
    /// a 60-second limit, as on Telegram and WhatsApp.
    case videoNote

    static let videoNoteMaxDuration: TimeInterval = 60

    var initialPosition: AVCaptureDevice.Position {
        self == .videoNote ? .front : .back
    }

    var recordsAudio: Bool { self == .videoNote }

    /// A note is shown small and round, so it does not need a photo-sized frame.
    var sessionPreset: AVCaptureSession.Preset {
        self == .videoNote ? .vga640x480 : .photo
    }

    var maxRecordedDuration: CMTime {
        self == .videoNote
            ? CMTime(seconds: Self.videoNoteMaxDuration, preferredTimescale: 600)
            : .invalid
    }
}

// MARK: - SwiftUI wrapper

struct ChatCameraPreviewRepresentable: UIViewRepresentable {
    @ObservedObject var sessionController: ChatCameraSessionController
    var profile: ChatCameraProfile = .standard
    var onPhotoCaptured: (UIImage) -> Void
    var onVideoCaptured: (URL) -> Void
    /// A recording that ended without a file to show for it.
    var onVideoFailed: () -> Void = {}

    func makeUIView(context: Context) -> ChatCameraPreviewUIView {
        let view = ChatCameraPreviewUIView(profile: profile)
        view.onPhotoCaptured = onPhotoCaptured
        view.onVideoCaptured = onVideoCaptured
        view.onVideoFailed = onVideoFailed
        sessionController.previewView = view
        return view
    }

    func updateUIView(_ uiView: ChatCameraPreviewUIView, context: Context) {
        uiView.onPhotoCaptured = onPhotoCaptured
        uiView.onVideoCaptured = onVideoCaptured
        uiView.onVideoFailed = onVideoFailed
        sessionController.previewView = uiView
    }
}

// MARK: - UIKit preview (preview layer only — no duplicate chrome)

final class ChatCameraPreviewUIView: UIView {

    var onPhotoCaptured: ((UIImage) -> Void)?
    var onVideoCaptured: ((URL) -> Void)?
    var onVideoFailed: (() -> Void)?

    private let profile: ChatCameraProfile
    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var currentCameraPosition: AVCaptureDevice.Position
    private var isRecording = false

    init(profile: ChatCameraProfile = .standard) {
        self.profile = profile
        self.currentCameraPosition = profile.initialPosition
        super.init(frame: .zero)
        backgroundColor = .black
        if ChatCameraAvailability.isCameraAvailable {
            setupCamera()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer?.frame = bounds
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = profile.sessionPreset

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
            let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        let photoOut = AVCapturePhotoOutput()
        let movieOut = AVCaptureMovieFileOutput()
        movieOut.maxRecordedDuration = profile.maxRecordedDuration

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        // Without a microphone input the file has no sound at all. Asking for
        // it prompts for microphone access the first time.
        if profile.recordsAudio,
           let microphone = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        if session.canAddOutput(photoOut) { session.addOutput(photoOut) }
        if session.canAddOutput(movieOut) { session.addOutput(movieOut) }
        session.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds
        layer.insertSublayer(previewLayer, at: 0)

        captureSession = session
        videoPreviewLayer = previewLayer
        photoOutput = photoOut
        movieOutput = movieOut

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func capturePhoto() {
        guard ChatCameraAvailability.isCameraAvailable,
              let photoOutput else {
            // Simulator fallback — solid placeholder so preview flow still works
            let size = CGSize(width: 1080, height: 1920)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                UIColor.darkGray.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            onPhotoCaptured?(image)
            return
        }

        let settings = AVCapturePhotoSettings()
        let delegate = PhotoCaptureDelegate { [weak self] image in
            guard let image else { return }
            DispatchQueue.main.async {
                self?.onPhotoCaptured?(image)
            }
        }
        photoOutput.capturePhoto(with: settings, delegate: delegate)
        objc_setAssociatedObject(photoOutput, &PhotoCaptureDelegate.associationKey, delegate, .OBJC_ASSOCIATION_RETAIN)
    }

    func flipCamera() {
        guard let captureSession else { return }
        captureSession.beginConfiguration()

        // The camera input specifically: with a microphone in the session the
        // first input is not necessarily the camera.
        if let currentInput = captureSession.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) }) {
            captureSession.removeInput(currentInput)
        }

        currentCameraPosition = currentCameraPosition == .back ? .front : .back
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
            let newInput = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(newInput)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(newInput)
        captureSession.commitConfiguration()
    }

    func startVideoRecording() {
        guard let movieOutput, !isRecording else { return }
        isRecording = true

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let delegate = VideoCaptureDelegate { [weak self] url in
            DispatchQueue.main.async {
                self?.isRecording = false
                if let url {
                    self?.onVideoCaptured?(url)
                } else {
                    self?.onVideoFailed?()
                }
            }
        }
        movieOutput.startRecording(to: outputURL, recordingDelegate: delegate)
        objc_setAssociatedObject(movieOutput, &VideoCaptureDelegate.associationKey, delegate, .OBJC_ASSOCIATION_RETAIN)
    }

    func stopVideoRecording() {
        guard isRecording else { return }
        movieOutput?.stopRecording()
    }

    deinit {
        captureSession?.stopRunning()
    }
}

// MARK: - Capture delegates (retained via associated object)

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    static var associationKey: UInt8 = 0
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}

private final class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    static var associationKey: UInt8 = 0
    private let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // Reaching `maxRecordedDuration` is reported as an error, but the file
        // is complete: AVFoundation says so in the error's user info.
        let finished = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        completion(finished ? outputFileURL : nil)
    }
}
