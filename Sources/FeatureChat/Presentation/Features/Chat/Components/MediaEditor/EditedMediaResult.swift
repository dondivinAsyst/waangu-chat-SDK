//
//  EditedMediaResult.swift
//  FeatureChat
//

import UIKit

/// Output of the chat media editor, ready for the send pipeline.
enum EditedMediaResult {
    /// Gallery item sent without bitmap edits (filter/crop/draw/text).
    case uneditedGallery(GalleryMedia)
    /// Exported bitmap after edits.
    case exportedImage(UIImage, jpegData: Data?)
    /// Exported or original video URL.
    case exportedVideo(URL)
}

extension EditedMediaResult {
    var hasBitmapEdits: Bool {
        switch self {
        case .uneditedGallery: return false
        case .exportedImage, .exportedVideo: return true
        }
    }
}
