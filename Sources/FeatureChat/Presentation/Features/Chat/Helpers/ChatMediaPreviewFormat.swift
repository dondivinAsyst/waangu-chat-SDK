//
//  ChatMediaPreviewFormat.swift
//  FeatureChat
//

import CoreGraphics

/// How the inline preview carried on `message.thumbnail` is encoded.
///
/// This preview is not a nicety — it is the first thing a media bubble draws, on
/// the frame the row appears, before anything has been read from disk or the
/// network. So it has to be recognisable as the photo and it has to keep the
/// photo's proportions, which is what lets the bubble reserve its final height
/// immediately instead of resizing when the real image lands.
///
/// Defined in one place because two send paths produce it — the camera, through
/// `imageToDataURL`, and the gallery, through `generateAndSaveThumbnail` — and
/// when they disagreed the two looked visibly different in the same thread.
///
/// Deliberately not the defaults on `imageToDataURL` itself: that helper also
/// encodes status/story thumbnails, which are displayed much smaller and have no
/// reason to carry the extra bytes.
enum ChatMediaPreviewFormat {
    /// Longest edge, in points. Large enough to read as the picture at bubble
    /// width; small enough that the encoded string stays in the low tens of KB.
    static let maxDimension: CGFloat = 256

    /// JPEG compression. The previous 0.005–0.01 was low enough that the preview
    /// was mostly block artefacts, which is tolerable for something never shown
    /// and not for something shown first.
    static let quality: CGFloat = 0.5
}
