//
//  VideoNoteRecorderViewModel.swift
//  FeatureChat
//

import Combine
import Foundation

/// Drives `VideoNoteRecorderSheet`: one recording, handed over the moment it
/// stops, as on Telegram and WhatsApp — there is no review step.
@MainActor
final class VideoNoteRecorderViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case recording
        /// Stopped, waiting for AVFoundation to close the file.
        case finishing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0

    let sessionController = ChatCameraSessionController()
    let maxDuration = ChatCameraProfile.videoNoteMaxDuration

    /// Anything shorter is a slip of the finger rather than a note, and is
    /// thrown away instead of sent.
    static let minimumDuration: TimeInterval = 1

    private let onRecorded: (URL) -> Void
    private var clock: AnyCancellable?
    private var startedAt: Date?
    private var discardsRecording = false

    init(onRecorded: @escaping (URL) -> Void) {
        self.onRecorded = onRecorded
    }

    /// How much of the 60 seconds has been used, for the ring around the circle.
    var progress: Double {
        min(elapsed / maxDuration, 1)
    }

    func toggleRecording() {
        switch phase {
        case .idle:      start()
        case .recording: stop()
        case .finishing: break
        }
    }

    func start() {
        guard phase == .idle else { return }
        discardsRecording = false
        elapsed = 0
        startedAt = Date()
        phase = .recording
        sessionController.startVideoRecording()
        clock = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in self?.tick(now) }
    }

    /// Stops and sends — unless it was too short to be a note.
    func stop() {
        guard phase == .recording else { return }
        discardsRecording = elapsed < Self.minimumDuration
        finish()
    }

    /// Leaving the sheet mid-recording throws the recording away.
    func cancel() {
        guard phase == .recording else { return }
        discardsRecording = true
        finish()
    }

    func didFinishRecording(at url: URL) {
        stopClock()
        phase = .idle
        if discardsRecording {
            discardsRecording = false
            try? FileManager.default.removeItem(at: url)
            return
        }
        onRecorded(url)
    }

    func didFailRecording() {
        stopClock()
        discardsRecording = false
        phase = .idle
    }

    // MARK: - Private

    private func finish() {
        stopClock()
        phase = .finishing
        sessionController.stopVideoRecording()
    }

    private func tick(_ now: Date) {
        guard let startedAt else { return }
        // AVFoundation stops the file at the limit by itself and then reports
        // it as finished; this only holds the clock there in the meantime.
        elapsed = min(now.timeIntervalSince(startedAt), maxDuration)
        if elapsed >= maxDuration {
            stopClock()
            phase = .finishing
        }
    }

    private func stopClock() {
        clock?.cancel()
        clock = nil
    }
}
