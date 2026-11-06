//
//  MediaPlaceholderFill.swift
//  FeatureChat
//

import SwiftUI

/// What a media bubble shows when it has nothing to show yet.
///
/// Replaces a `resizable().scaledToFit()` SF Symbol, which sized itself from the
/// symbol's own proportions and so gave the row a height unrelated to the photo
/// that would land in it. This fills whatever box the bubble reserved instead, so
/// the real image replaces it without the row changing size.
///
/// Only reached when a message carries no inline preview at all; anything sent
/// through the app has one.
struct MediaPlaceholderFill: View {
    var isVideo: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(fill)
            .overlay {
                Image(systemName: isVideo ? "video.fill" : "photo.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.35))
            }
    }

    /// A quiet gradient rather than a flat block, so an image that has not arrived
    /// still reads as a picture frame instead of a rendering error.
    private var fill: LinearGradient {
        let base = colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.10)
        return LinearGradient(
            colors: [base.opacity(0.75), base],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
