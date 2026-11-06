import SwiftUI

/// Drag and selection state shared between a `WSegmentedSwitcher` and whatever
/// content area is swipeable.
///
/// Lives outside any View file: it holds state and fires haptics, so it is not
/// a view concern.
@MainActor
public final class WSegmentedSwitcherModel<Item: Hashable>: ObservableObject {

    @Published public private(set) var selection: Item
    @Published var dragTranslation: CGFloat = 0
    @Published var isDragging: Bool = false

    /// Width of one segment, published by the strip once it has been laid out.
    var segmentWidth: CGFloat = 0

    /// Called whenever the selection actually changes, tap or swipe alike.
    public var onChange: ((Item) -> Void)?

    private let haptics = SelectionHaptics()

    public static var settleAnimation: Animation {
        .interactiveSpring(response: 0.3, dampingFraction: 0.8)
    }

    public init(selection: Item) {
        self.selection = selection
    }

    /// Force the selection without animation or feedback — for external changes
    /// (a deep link, a restored draft) that the user did not drive.
    public func set(_ item: Item) {
        guard item != selection else { return }
        selection = item
    }

    /// Commit a selection the user drove. Fires the haptic at the snap.
    public func select(_ item: Item, animated: Bool = true) {
        guard item != selection else {
            withAnimation(Self.settleAnimation) { dragTranslation = 0 }
            return
        }

        haptics.changed()

        let apply = {
            self.selection = item
            self.dragTranslation = 0
        }
        animated ? withAnimation(Self.settleAnimation, apply) : apply()

        onChange?(item)
    }

    /// Warm the Taptic engine ahead of a tap.
    public func prepareHaptics() {
        haptics.prepare()
    }

    // MARK: - Drag

    func beginDrag() {
        guard !isDragging else { return }
        isDragging = true
        haptics.prepare()
    }

    func updateDrag(_ translation: CGFloat) {
        dragTranslation = SegmentedSwitcherGeometry.rubberBanded(
            translation,
            limit: max(segmentWidth, 1)
        )
    }

    func endDrag(translation: CGFloat, predictedOvershoot: CGFloat, items: [Item]) {
        guard isDragging else { return }
        isDragging = false

        guard let current = items.firstIndex(of: selection) else {
            withAnimation(Self.settleAnimation) { dragTranslation = 0 }
            return
        }

        let target = SegmentedSwitcherGeometry.snapIndex(
            from: current,
            translation: translation,
            segmentWidth: segmentWidth,
            predictedOvershoot: predictedOvershoot,
            count: items.count
        )

        select(items[target])
    }

    /// 0…1 emphasis transfer while a drag is in flight.
    func dragProgress() -> CGFloat {
        guard isDragging else { return 0 }
        return SegmentedSwitcherGeometry.progress(
            translation: dragTranslation,
            segmentWidth: segmentWidth
        )
    }

    /// -1 toward the previous segment, +1 toward the next, 0 when idle or when
    /// the neighbour in that direction does not exist.
    func dragDirection(in items: [Item]) -> Int {
        guard isDragging, dragTranslation != 0,
              let current = items.firstIndex(of: selection) else { return 0 }

        let step = dragTranslation < 0 ? 1 : -1
        guard items.indices.contains(current + step) else { return 0 }
        return step
    }
}

// MARK: - Content swipe

public extension View {
    /// Lets a horizontal drag over this view drive a `WSegmentedSwitcher`.
    ///
    /// Attach to the content area, not the strip — the strip is already
    /// draggable on its own.
    ///
    /// `minimumDistance` keeps taps on embedded controls intact, and the axis
    /// check keeps a vertical scroll from being read as a segment change.
    func wSegmentedSwipe<Item: Hashable>(
        _ model: WSegmentedSwitcherModel<Item>,
        items: [Item],
        minimumDistance: CGFloat = 20
    ) -> some View {
        contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: minimumDistance)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        model.beginDrag()
                        model.updateDrag(value.translation.width)
                    }
                    .onEnded { value in
                        model.endDrag(
                            translation: value.translation.width,
                            predictedOvershoot: value.predictedEndTranslation.width - value.translation.width,
                            items: items
                        )
                    }
            )
    }
}
