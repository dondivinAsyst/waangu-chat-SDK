//
//  VideoNoteRecorderSheet.swift
//  FeatureChat
//

import WaanguCoreKit
import WaanguSharedUI
import SwiftUI

/// Records a `VIDEO_NOTE`: the front camera inside a circle, a ring that fills
/// over the 60 seconds, and the note sent as soon as recording stops.
///
/// Opened by a long press on the composer's camera button.
struct VideoNoteRecorderSheet: View {
    @StateObject private var model: VideoNoteRecorderViewModel
    let translationService: (any TranslationServiceProtocol)?
    let onDismiss: () -> Void

    private static let diameter: CGFloat = min(UIScreen.main.bounds.width * 0.75, 320)
    private static let ringWidth: CGFloat = 5

    init(
        translationService: (any TranslationServiceProtocol)?,
        onRecorded: @escaping (URL) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: VideoNoteRecorderViewModel(onRecorded: onRecorded))
        self.translationService = translationService
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 20) {
            header

            Spacer(minLength: 0)

            noteCircle

            Text(timeText)
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .foregroundStyle(model.phase == .recording ? AppColors.primary : .secondary)

            Text(t(ChatTranslationKeys.CHAT_VIDEO_NOTE_INSTRUCTION, fallback: "Tap the button to start recording. Tap again to send. Up to 60 seconds."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)

            controls
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .onDisappear {
            // Swiped down mid-recording: nothing is sent.
            model.cancel()
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(t(ChatTranslationKeys.CHAT_VIDEO_NOTE_TITLE, fallback: "Video note"))
                .font(.headline)

            HStack {
                Button(t(ChatTranslationKeys.CHAT_CANCEL, fallback: "Cancel")) {
                    model.cancel()
                    onDismiss()
                }
                .foregroundStyle(AppColors.primary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Circle

    private var noteCircle: some View {
        ZStack {
            Group {
                if ChatCameraAvailability.isCameraAvailable {
                    ChatCameraPreviewRepresentable(
                        sessionController: model.sessionController,
                        profile: .videoNote,
                        onPhotoCaptured: { _ in },
                        onVideoCaptured: { url in model.didFinishRecording(at: url) },
                        onVideoFailed: { model.didFailRecording() }
                    )
                } else {
                    Color.black.overlay {
                        Text(t(ChatTranslationKeys.CHAT_VIDEO_NOTE_CAMERA_UNAVAILABLE, fallback: "The camera is not available on this device."))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(32)
                    }
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .clipShape(Circle())

            Circle()
                .stroke(AppColors.primary.opacity(0.15), lineWidth: Self.ringWidth)

            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(AppColors.primary, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: model.progress)
        }
        .frame(
            width: Self.diameter + Self.ringWidth * 2 + 8,
            height: Self.diameter + Self.ringWidth * 2 + 8
        )
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            // Keeps the record button centred against the flip button.
            Color.clear.frame(width: 44, height: 44)

            Spacer()

            recordButton

            Spacer()

            Button {
                model.sessionController.flipCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 44, height: 44)
            }
            .disabled(model.phase != .idle || !ChatCameraAvailability.isCameraAvailable)
            .accessibilityLabel(t(ChatTranslationKeys.CALLS_FLIP_CAMERA, fallback: "Flip camera"))
        }
        .padding(.horizontal, 40)
    }

    private var recordButton: some View {
        let isRecording = model.phase == .recording
        return Button {
            model.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .stroke(AppColors.primary, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: 62, height: 62)
                Image(systemName: isRecording ? "arrow.up" : "video.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .disabled(model.phase == .finishing || !ChatCameraAvailability.isCameraAvailable)
        .accessibilityLabel(
            isRecording
                ? t(ChatTranslationKeys.CHAT_A11Y_SEND_MESSAGE, fallback: "Send message")
                : t(ChatTranslationKeys.CHAT_A11Y_RECORD_VIDEO_NOTE, fallback: "Record video note")
        )
    }

    // MARK: - Helpers

    private var timeText: String {
        "\(format(model.elapsed)) / \(format(model.maxDuration))"
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func t(_ key: String, fallback: String) -> String {
        translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE)
            .value ?? fallback
    }
}
