//
//  CameraFilmstripView.swift
//  FeatureChat
//

import Photos
import SwiftUI

struct CameraFilmstripView: View {
    let mediaItems: [GalleryMedia]
    var onSelect: (GalleryMedia) -> Void

    private let thumbWidth: CGFloat = 72
    private let thumbHeight: CGFloat = 96

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(mediaItems) { media in
                    CameraFilmstripCell(
                        media: media,
                        width: thumbWidth,
                        height: thumbHeight,
                        onTap: { onSelect(media) }
                    )
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: thumbHeight + 4)
        .padding(.bottom, 10)
    }
}

// MARK: - Cell

private struct CameraFilmstripCell: View {
    let media: GalleryMedia
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if media.type == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let size = CGSize(width: width * 2, height: height * 2)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: media.asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                thumbnail = image
            }
        }
    }
}
