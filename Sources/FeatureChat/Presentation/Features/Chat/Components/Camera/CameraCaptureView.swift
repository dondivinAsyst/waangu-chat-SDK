//
//  CameraCaptureView.swift
//  FeatureChat
//

import SwiftUI

struct CameraCaptureView: View {

    enum CaptureMode: String, CaseIterable {
        case video = "VIDEO"
        case photo = "PHOTO"
    }

    @ObservedObject var mediaViewModel: PHMediaManagerViewModel
    @ObservedObject var sessionController: ChatCameraSessionController

    var onMediaSelected: (GalleryMedia) -> Void
    var onCaptured: (CapturedCameraMedia) -> Void
    var onDismiss: () -> Void

    @State private var selectedMode: CaptureMode = .photo
    @State private var isRecordingVideo = false
    @State private var didAppear = false

    private var filmstripItems: [GalleryMedia] {
        Array(mediaViewModel.mediaItems.prefix(20))
    }

    var body: some View {
        ZStack {
            if ChatCameraAvailability.isCameraAvailable {
                ChatCameraPreviewRepresentable(
                    sessionController: sessionController,
                    onPhotoCaptured: { image in
                        let data = image.jpegData(compressionQuality: 0.9)
                        onCaptured(.image(image, jpegData: data))
                    },
                    onVideoCaptured: { url in
                        onCaptured(.video(url))
                    }
                )
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                CameraFilmstripView(
                    mediaItems: filmstripItems,
                    onSelect: { media in
                        mediaViewModel.prepareMediaForPreview(media, completion: onMediaSelected)
                    }
                )
                controlsRow
                modeSelector
            }
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            mediaViewModel.requestPhotoLibraryAccess()
            if mediaViewModel.mediaItems.isEmpty {
                mediaViewModel.loadMediaFromLibrary()
            }
            withAnimation(ChatMediaOpenAnimation.chromeEnter) {
                didAppear = true
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }

            Spacer()

            Button { } label: {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Shutter / gallery / flip row

    private var controlsRow: some View {
        HStack {
            Button {
                if let first = filmstripItems.first {
                    mediaViewModel.prepareMediaForPreview(first, completion: onMediaSelected)
                }
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, 30)
            .opacity(filmstripItems.isEmpty ? 0.4 : 1)
            .disabled(filmstripItems.isEmpty)

            Spacer()

            shutterButton

            Spacer()

            Button {
                sessionController.flipCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .padding(.trailing, 30)
        }
        .padding(.bottom, 14)
    }

    private var shutterButton: some View {
        Button {
            handleShutterTap()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(isRecordingVideo ? Color.red : Color.white)
                    .frame(width: isRecordingVideo ? 36 : 64, height: isRecordingVideo ? 36 : 64)
                    .animation(.easeInOut(duration: 0.2), value: isRecordingVideo)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    guard selectedMode == .video else { return }
                    isRecordingVideo = true
                    sessionController.startVideoRecording()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    if isRecordingVideo {
                        isRecordingVideo = false
                        sessionController.stopVideoRecording()
                    }
                }
        )
    }

    private func handleShutterTap() {
        switch selectedMode {
        case .photo:
            sessionController.capturePhoto()
        case .video:
            if isRecordingVideo {
                isRecordingVideo = false
                sessionController.stopVideoRecording()
            } else {
                isRecordingVideo = true
                sessionController.startVideoRecording()
            }
        }
    }

    // MARK: - Mode selector

    private var modeSelector: some View {
        HStack(spacing: 28) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedMode == mode ? .yellow : .white.opacity(0.7))
                }
            }
        }
        .padding(.bottom, 24)
    }
}

#Preview {
    CameraCaptureView(
        mediaViewModel: PHMediaManagerViewModel(mediaManager: PHMediaManager()),
        sessionController: ChatCameraSessionController(),
        onMediaSelected: { _ in },
        onCaptured: { _ in },
        onDismiss: {}
    )
}
