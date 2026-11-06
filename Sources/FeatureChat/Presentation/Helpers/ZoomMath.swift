import UIKit

/// Zoom and centering math for `MediaViewerPageCell`'s scroll view.
enum ZoomMath {

    /// The rect to zoom to so `center` ends up centered at `scale`.
    static func zoomRect(scale: CGFloat, center: CGPoint, in boundsSize: CGSize) -> CGRect {
        guard scale > 0 else {
            return CGRect(origin: .zero, size: boundsSize)
        }
        let size = CGSize(width: boundsSize.width / scale, height: boundsSize.height / scale)
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Insets that keep content centered while it is smaller than the viewport.
    static func centeringInset(contentSize: CGSize, boundsSize: CGSize) -> UIEdgeInsets {
        let vertical = max(0, (boundsSize.height - contentSize.height) / 2)
        let horizontal = max(0, (boundsSize.width - contentSize.width) / 2)
        return UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
}
