import CoreGraphics

/// Pure geometry for `WSegmentedSwitcher`.
///
/// Free of SwiftUI and UIKit so the snap rules are unit-testable without a
/// running view. Dragging **left** (negative translation) advances toward the
/// next segment, matching how paging reads on iOS.
public enum SegmentedSwitcherGeometry {

    /// Fraction of a segment the finger must cross before the strip commits.
    public static let commitFraction: CGFloat = 0.5

    /// Predicted overshoot, in points, past which a flick commits regardless of
    /// how far the finger actually travelled.
    ///
    /// This is deliberately expressed in points rather than points-per-second:
    /// SwiftUI's `DragGesture` exposes `predictedEndTranslation`, not a velocity,
    /// and converting between them would just invent precision we don't have.
    public static let flickOvershoot: CGFloat = 60

    private static let rubberBandCoefficient: CGFloat = 0.55

    /// Index the strip should settle on when the finger lifts.
    ///
    /// - Parameter predictedOvershoot: `predictedEndTranslation.width - translation.width`.
    public static func snapIndex(
        from current: Int,
        translation: CGFloat,
        segmentWidth: CGFloat,
        predictedOvershoot: CGFloat,
        count: Int
    ) -> Int {
        guard count > 0 else { return 0 }
        guard segmentWidth > 0 else { return clamp(current, count: count) }

        let crossedDistance = abs(translation) > segmentWidth * commitFraction
        let flicked = abs(predictedOvershoot) > flickOvershoot

        guard crossedDistance || flicked else {
            return clamp(current, count: count)
        }

        // Distance wins when the finger actually travelled; a flick only decides
        // direction when it barely moved. This keeps a slow drag back past centre
        // behaving as a cancel.
        let direction: CGFloat = crossedDistance ? translation : predictedOvershoot
        return clamp(current + (direction < 0 ? 1 : -1), count: count)
    }

    /// Continuous 0…1 progress across one segment, for interpolating the label
    /// colour and the indicator while the finger is still down.
    public static func progress(translation: CGFloat, segmentWidth: CGFloat) -> CGFloat {
        guard segmentWidth > 0 else { return 0 }
        return min(abs(translation) / segmentWidth, 1)
    }

    /// Standard iOS rubber-band resistance, for dragging past either end.
    public static func rubberBanded(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        let resisted = (1 - (1 / (abs(offset) * rubberBandCoefficient / limit + 1))) * limit
        return offset < 0 ? -resisted : resisted
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        min(max(index, 0), count - 1)
    }
}
