import CoreGraphics

/// Thresholds for the media viewer's interactive drag-to-dismiss gesture.
///
/// Pure so the thresholds can be tested as a table without a simulator.
enum DismissDecision {

    enum Outcome: Equatable {
        case finish
        case cancel
    }

    /// Points of vertical travel past which release dismisses.
    static let translationThreshold: CGFloat = 120

    /// Points-per-second past which release dismisses regardless of travel.
    static let velocityThreshold: CGFloat = 800

    /// Smallest scale the photo shrinks to at full drag progress.
    static let minimumScale: CGFloat = 0.6

    /// Only vertical motion counts — horizontal drag belongs to the pager.
    ///
    /// Uses `abs` so an upward flick dismisses too, matching both WhatsApp and
    /// the gesture the previous carousel already shipped.
    static func outcome(translation: CGSize, velocity: CGSize) -> Outcome {
        if abs(velocity.height) > velocityThreshold { return .finish }
        if abs(translation.height) > translationThreshold { return .finish }
        return .cancel
    }

    /// 0–1 drag progress, measured against half the container height.
    static func progress(translation: CGSize, in bounds: CGRect) -> CGFloat {
        guard bounds.height > 0 else { return 0 }
        return min(abs(translation.height) / (bounds.height / 2), 1)
    }

    /// Scale the dragged photo shrinks to at the given progress.
    static func scale(forProgress progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return 1 - clamped * (1 - minimumScale)
    }
}
