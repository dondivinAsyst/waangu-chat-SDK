import SwiftUI
import UIKit

/// Source rects for the media viewer's hero transition, keyed by `codeMessage`.
///
/// Looked up at transition time rather than captured at tap time, which is what
/// lets dismiss fly back to whichever page the user swiped to rather than the one
/// they opened.
///
/// Only `hiddenAnchorID` is published. The rect store deliberately is not:
/// bubbles re-report their rect on every layout pass while scrolling, and
/// publishing that would re-render the message list continuously.
@MainActor
final class MediaHeroAnchorRegistry: ObservableObject {

    static let shared = MediaHeroAnchorRegistry()

    /// The anchor whose source view should render transparent, because its
    /// snapshot is currently flying. Nil at rest.
    @Published var hiddenAnchorID: String?

    final class Anchor {
        let rect: CGRect
        let image: UIImage?
        weak var sourceView: UIView?

        init(rect: CGRect, image: UIImage?, sourceView: UIView?) {
            self.rect = rect
            self.image = image
            self.sourceView = sourceView
        }
    }

    private var anchors: [String: Anchor] = [:]

    init() {}

    func register(id: String, rect: CGRect, image: UIImage?, sourceView: UIView?) {
        anchors[id] = Anchor(rect: rect, image: image, sourceView: sourceView)
    }

    func unregister(id: String) {
        anchors.removeValue(forKey: id)
    }

    func anchor(for id: String) -> Anchor? {
        anchors[id]
    }

    /// The anchor for `id`, but only when it is genuinely on screen and worth
    /// flying back to.
    ///
    /// SwiftUI anchors register no `sourceView` — there is no `UIView` to hand
    /// over — so window membership cannot be the only test. An on-screen rect
    /// counts too. When this returns nil the dismiss animator fades out in place
    /// instead of flying to a stale rect.
    func flyableAnchor(for id: String) -> Anchor? {
        guard let anchor = anchors[id], anchor.rect != .zero else { return nil }

        let onScreen = anchor.sourceView?.window != nil
            || UIScreen.main.bounds.intersects(anchor.rect)
        return onScreen ? anchor : nil
    }
}
