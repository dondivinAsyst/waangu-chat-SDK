//
//  CameraMediaTypes.swift
//  FeatureChat
//

import AVFoundation
import Photos
import SwiftUI
import UIKit

// MARK: - Captured camera output

enum CapturedCameraMedia: Equatable {
    case image(UIImage, jpegData: Data?)
    case video(URL)
    /// Recorded in `VideoNoteRecorderSheet`. Sent as it is, without the editor,
    /// as a `VIDEO_NOTE`.
    case videoNote(URL)

    static func == (lhs: CapturedCameraMedia, rhs: CapturedCameraMedia) -> Bool {
        switch (lhs, rhs) {
        case (.image, .image): return true
        case (.video(let l), .video(let r)): return l == r
        case (.videoNote(let l), .videoNote(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - Unified preview model (gallery pick or fresh capture)

struct PreviewMediaItem: Identifiable {
    let id = UUID()
    let source: Source

    enum Source {
        case gallery(GalleryMedia)
        case captured(CapturedCameraMedia)
    }

    var galleryMedia: GalleryMedia? {
        if case .gallery(let media) = source { return media }
        return nil
    }

    var capturedMedia: CapturedCameraMedia? {
        if case .captured(let media) = source { return media }
        return nil
    }

    var previewImage: UIImage? {
        switch source {
        case .gallery(let media):
            return media.highQualityImage
        case .captured(let captured):
            if case .image(let image, _) = captured { return image }
            return nil
        }
    }

    var isVideo: Bool {
        switch source {
        case .gallery(let media): return media.type == .video
        case .captured(let captured):
            switch captured {
            case .video, .videoNote: return true
            case .image: return false
            }
        }
    }

    var videoURL: URL? {
        switch source {
        case .gallery(let media):
            guard media.type == .video, let uri = media.uri, !uri.isEmpty else { return nil }
            if let url = URL(string: uri), url.isFileURL || url.scheme != nil { return url }
            return URL(fileURLWithPath: uri)
        case .captured(let captured):
            switch captured {
            case .video(let url), .videoNote(let url): return url
            case .image: return nil
            }
        }
    }
}

// MARK: - Camera availability

enum ChatCameraAvailability {
    static var isCameraAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return AVCaptureDevice.default(for: .video) != nil
        #endif
    }
}
