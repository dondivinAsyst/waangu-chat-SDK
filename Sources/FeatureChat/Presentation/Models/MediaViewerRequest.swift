import Foundation

/// What to show and where to start.
///
/// Replaces `AlbumPresentation`, which also carried a source frame, a transition
/// image and a carousel mode. Geometry now comes from `MediaHeroAnchorRegistry`
/// at transition time instead of being captured at tap time.
struct MediaViewerRequest: Equatable {
    let items: [MediaViewerItem]
    let startIndex: Int
}
