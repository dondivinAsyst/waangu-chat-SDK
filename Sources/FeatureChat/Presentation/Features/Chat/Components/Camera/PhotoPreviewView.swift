//
//  PhotoPreviewView.swift
//  FeatureChat
//

import AVKit
import SwiftUI

struct PhotoPreviewView: View {

    let previewMedia: PreviewMediaItem
    let recipientName: String
    let onSend: (String?) -> Void
    let onDismiss: () -> Void

    @State private var caption: String = ""
    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                mediaPreview
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadPreviewIfNeeded() }
    }

    // MARK: - Media preview

    @ViewBuilder
    private var mediaPreview: some View {
        if previewMedia.isVideo, let url = previewMedia.videoURL {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(maxWidth: .infinity)
        } else if let image = loadedImage ?? previewMedia.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    // MARK: - Top toolbar

    private var topBar: some View {
        HStack(spacing: 22) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .toolbarIconStyle()
            }

            Spacer()

            Button { } label: {
                Image(systemName: "square.and.arrow.down")
                    .toolbarIconStyle()
            }

            Button { } label: {
                Text("HD")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    )
            }

            Button { } label: {
                Image(systemName: "crop")
                    .toolbarIconStyle()
            }

            Button { } label: {
                Image(systemName: "seal")
                    .toolbarIconStyle()
            }

            Button { } label: {
                Text("Aa")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Button { } label: {
                Image(systemName: "pencil.tip")
                    .toolbarIconStyle()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Caption + recipient + send

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "paperclip")
                    .foregroundStyle(.white.opacity(0.85))
                    .font(.system(size: 16))
                    .padding(.leading, 4)

                TextField("", text: $caption, prompt: Text("Add a caption...")
                    .foregroundStyle(.white.opacity(0.55)))
                    .foregroundStyle(.white)
                    .font(.system(size: 16))

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.2)
                        .frame(width: 20, height: 20)
                    Text("1")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.12))
            )
            .padding(.horizontal, 10)

            HStack {
                Text(recipientName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.white.opacity(0.10))
                    )
                    .padding(.leading, 14)

                Spacer()

                Button {
                    let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSend(trimmed.isEmpty ? nil : trimmed)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Color.green))
                }
                .padding(.trailing, 14)
            }
        }
        .padding(.bottom, 20)
    }

    private func loadPreviewIfNeeded() {
        guard loadedImage == nil,
              let galleryMedia = previewMedia.galleryMedia,
              galleryMedia.highQualityImage == nil else { return }

        if galleryMedia.type == .image {
            PHMediaManagerViewModel.loadPreviewImage(for: galleryMedia.asset) { image in
                loadedImage = image
            }
        }
    }
}

// MARK: - Shared icon styling

private extension Image {
    func toolbarIconStyle() -> some View {
        self
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
    }
}

#Preview {
    PhotoPreviewView(
        previewMedia: PreviewMediaItem(source: .captured(.image(UIImage(systemName: "photo")!, jpegData: nil))),
        recipientName: "Armand",
        onSend: { _ in },
        onDismiss: {}
    )
}
