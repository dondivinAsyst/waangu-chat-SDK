//
//  CallCameraController.swift
//  FeatureChat
//
//  Owns the local camera capture session for a video call.
//
//  Only a video input is attached: the microphone and audio route stay under
//  `VoipManager`/CallKit control, and adding a second audio input here would
//  fight the voice-chat AVAudioSession.
//
//  When the hardware and entitlement allow it, multitasking camera access is
//  enabled so the capture keeps producing frames while the call is in
//  Picture-in-Picture and the user is in another app.
//

// AVFoundation's capture types predate strict concurrency checking and are not
// Sendable, yet they are designed to be driven from a dedicated serial queue —
// which is exactly what `sessionQueue` below is. @preconcurrency keeps that
// intentional pattern from drowning the build in Sendable warnings.
@preconcurrency import AVFoundation
import Combine
import UIKit

@MainActor
final class CallCameraController: ObservableObject {

    enum Status: Equatable {
        case idle
        case denied
        case running
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var position: AVCaptureDevice.Position = .front

    /// Shared with every preview layer that renders this feed (inline and PiP).
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.waangu.call.camera.session")
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false

    // MARK: - Lifecycle

    /// Requests authorisation if needed, configures the session once, and runs it.
    func start() async {
        guard await ensureAuthorized() else {
            status = .denied
            return
        }

        if !isConfigured {
            let result = await configure(position: position)
            switch result {
            case .success:
                isConfigured = true
            case .failure(let message):
                status = .failed(message)
                return
            }
        }

        await withCheckedContinuation { continuation in
            sessionQueue.async { [session] in
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }

        status = .running
    }

    func stop() {
        let input = videoInput
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
            session.beginConfiguration()
            if let input {
                session.removeInput(input)
            }
            session.commitConfiguration()
        }
        videoInput = nil
        isConfigured = false
        status = .idle
    }

    /// Swaps between the front and back camera without tearing the session down.
    func flip() {
        let target: AVCaptureDevice.Position = (position == .front) ? .back : .front
        guard let device = Self.camera(at: target) else { return }

        sessionQueue.async { [session, videoInput] in
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            if let existing = videoInput {
                session.removeInput(existing)
            }

            guard let newInput = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(newInput) else {
                // Put the previous input back rather than leaving a dead session.
                if let existing = videoInput, session.canAddInput(existing) {
                    session.addInput(existing)
                }
                return
            }

            session.addInput(newInput)

            Task { @MainActor [weak self] in
                self?.videoInput = newInput
                self?.position = target
            }
        }
    }

    // MARK: - Configuration

    private enum ConfigureResult {
        case success
        case failure(String)
    }

    private func configure(position: AVCaptureDevice.Position) async -> ConfigureResult {
        guard let device = Self.camera(at: position) else {
            return .failure("No camera available at position \(position.rawValue)")
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            return .failure(ChatErrorStrings.cameraOpenFailed)
        }

        return await withCheckedContinuation { continuation in
            sessionQueue.async { [session] in
                session.beginConfiguration()
                session.sessionPreset = .high

                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    continuation.resume(returning: .failure("Camera input rejected by session"))
                    return
                }
                session.addInput(input)

                // Keeps frames flowing while the call runs in PiP / another app.
                // Requires com.apple.developer.avfoundation.multitasking-camera-access.
                if session.isMultitaskingCameraAccessSupported {
                    session.isMultitaskingCameraAccessEnabled = true
                }

                session.commitConfiguration()

                Task { @MainActor [weak self] in
                    self?.videoInput = input
                }
                continuation.resume(returning: .success)
            }
        }
    }

    private func ensureAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualWideCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }
}
