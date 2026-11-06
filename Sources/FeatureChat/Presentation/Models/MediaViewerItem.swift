import UIKit

/// One page in the media viewer.
///
/// Carries the thumbnail that is already in memory — the same `UIImage` the
/// bubble is rendering — so a page is never empty while full resolution decodes.
///
/// Deliberately carries no transfer state. It is a snapshot taken when the user
/// tapped, and a snapshot cannot describe something still in motion: a page built
/// while a download was running would have shown that state for as long as the
/// viewer stayed open, whatever the download went on to do. Live state belongs to
/// `FileUploadViewModel`, which the page's overlay observes directly; what this
/// type carries is only what is true of the file right now, and `fullResURL` and
/// `videoURL` already say it by being nil.
struct MediaViewerItem: Identifiable, Equatable {

    enum Kind: Equatable {
        case image
        case video
    }

    let id: String              // codeMessage
    let kind: Kind
    let thumbnail: UIImage?
    let fullResURL: URL?
    let videoURL: URL?
    let videoDuration: TimeInterval?
    let senderName: String
    let displayTime: String
    let caption: String
    let isSentByMe: Bool

    /// Identity comparison only: `UIImage` has no cheap value equality, and the
    /// pager only ever needs to know whether a page still refers to the same
    /// message.
    static func == (lhs: MediaViewerItem, rhs: MediaViewerItem) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind
    }
}
