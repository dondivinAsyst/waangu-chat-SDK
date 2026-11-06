import UIKit

/// Retains a single `UISelectionFeedbackGenerator` so the Taptic engine is warm
/// when a selection lands.
///
/// `prepare()` at gesture start is what removes the latency on the first buzz;
/// a freshly constructed generator cannot do that.
@MainActor
public final class SelectionHaptics {

    private let generator = UISelectionFeedbackGenerator()

    public init() {}

    /// Call at gesture start, or on touch-down for a tap.
    public func prepare() {
        generator.prepare()
    }

    /// Call at the moment the selection actually changes — not before.
    public func changed() {
        generator.selectionChanged()
        generator.prepare() // stay warm for a rapid second switch
    }
}
