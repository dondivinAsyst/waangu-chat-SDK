import AVFoundation
import CoreGraphics

/// Fitted rect math shared by the hero animators and the page cell.
///
/// Both sides must agree exactly: the animator flies a snapshot to this rect and
/// the cell lays its image view out at this rect for zoom scale 1. Computing it
/// in one place is what makes the handoff seamless rather than approximate.
enum HeroGeometry {

    /// The aspect-fitted, centered rect for `imageSize` inside `bounds`.
    ///
    /// Returns `bounds` unchanged when either size is degenerate — a failed
    /// decode must not produce NaN geometry that breaks the transition.
    static func targetRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        return AVMakeRect(aspectRatio: imageSize, insideRect: bounds)
    }
}
