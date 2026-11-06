import SwiftUI
import UIKit

// MARK: - Segment

/// One labelled segment. `id` is whatever the caller selects on — an enum case,
/// an index, a string.
public struct WSegment<Item: Hashable>: Identifiable {
    public let id: Item
    public let title: String

    public init(id: Item, title: String) {
        self.id = id
        self.title = title
    }
}

// MARK: - Style

public struct WSegmentedSwitcherStyle {

    public enum Indicator {
        case none
        /// A bar under the selected segment, spanning that segment's width.
        case underline(height: CGFloat, cornerRadius: CGFloat, inset: CGFloat)
    }

    public var font: Font
    public var selectedFont: Font?
    public var selectedColor: Color
    public var unselectedColor: Color
    public var background: Color
    public var indicator: Indicator
    public var indicatorColor: Color
    public var verticalPadding: CGFloat
    public var horizontalPadding: CGFloat
    public var selectedScale: CGFloat
    /// Letter spacing, for strips that use tracked small-caps labels.
    public var tracking: CGFloat
    /// Gap between the labels and the indicator.
    public var indicatorSpacing: CGFloat

    public init(
        font: Font = .system(size: 15, weight: .semibold),
        selectedFont: Font? = nil,
        selectedColor: Color,
        unselectedColor: Color,
        background: Color = .clear,
        indicator: Indicator = .none,
        indicatorColor: Color? = nil,
        verticalPadding: CGFloat = 16,
        horizontalPadding: CGFloat = 0,
        selectedScale: CGFloat = 1.0,
        tracking: CGFloat = 0,
        indicatorSpacing: CGFloat = 0
    ) {
        self.font = font
        self.selectedFont = selectedFont
        self.selectedColor = selectedColor
        self.unselectedColor = unselectedColor
        self.background = background
        self.indicator = indicator
        self.indicatorColor = indicatorColor ?? selectedColor
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.selectedScale = selectedScale
        self.tracking = tracking
        self.indicatorSpacing = indicatorSpacing
    }
}

public extension WSegmentedSwitcherStyle {

    /// The status composer: dark bar, amber selected label, no indicator.
    static var composer: Self {
        .init(
            font: .system(size: 15, weight: .semibold),
            selectedColor: Color(red: 1.0, green: 0.7, blue: 0.3),
            unselectedColor: .white,
            background: Color.black.opacity(0.92),
            indicator: .none,
            selectedScale: 1.08
        )
    }

    /// Wallet/Ride style: gliding underline, weight change on select.
    static func underline(
        tint: Color,
        unselected: Color = AppColors.iconLabel.opacity(0.7),
        font: Font = .system(size: 14, weight: .regular),
        selectedFont: Font = .system(size: 14, weight: .semibold),
        height: CGFloat = 3
    ) -> Self {
        .init(
            font: font,
            selectedFont: selectedFont,
            selectedColor: tint,
            unselectedColor: unselected,
            indicator: .underline(height: height, cornerRadius: height / 2, inset: 0),
            verticalPadding: 10
        )
    }

    /// Labels only, no indicator.
    static func plain(
        tint: Color,
        unselected: Color = .gray,
        font: Font = .system(size: 15, weight: .semibold)
    ) -> Self {
        .init(font: font, selectedColor: tint, unselectedColor: unselected, verticalPadding: 12)
    }
}

// MARK: - Switcher

/// A segmented switcher whose labels track the finger and whose selection snaps
/// with a haptic.
///
/// Two ways to use it:
///
/// * `init(segments:selection:style:)` — standalone. Taps and drags on the strip
///   work with no extra state at the call site.
/// * `init(segments:model:style:)` — shares a `WSegmentedSwitcherModel` with a
///   content area marked `.wSegmentedSwipe(...)`, so swiping the content moves
///   the strip too.
public struct WSegmentedSwitcher<Item: Hashable>: View {

    private enum Source {
        case bound(Binding<Item>)
        case shared(WSegmentedSwitcherModel<Item>)
    }

    private let segments: [WSegment<Item>]
    private let style: WSegmentedSwitcherStyle
    private let source: Source

    public init(
        segments: [WSegment<Item>],
        model: WSegmentedSwitcherModel<Item>,
        style: WSegmentedSwitcherStyle
    ) {
        self.segments = segments
        self.style = style
        self.source = .shared(model)
    }

    public init(
        segments: [WSegment<Item>],
        selection: Binding<Item>,
        style: WSegmentedSwitcherStyle
    ) {
        self.segments = segments
        self.style = style
        self.source = .bound(selection)
    }

    public var body: some View {
        switch source {
        case let .shared(model):
            // Caller owns the model — observe it, never take ownership.
            SegmentedStrip(segments: segments, model: model, style: style)
        case let .bound(selection):
            // No model supplied, so one is created and kept alive here. Split
            // into its own view because @StateObject cannot be conditional.
            OwnedSegmentedStrip(segments: segments, selection: selection, style: style)
        }
    }
}

// MARK: - Binding-backed wrapper

/// Owns a model on the caller's behalf and reconciles it with their `Binding`.
private struct OwnedSegmentedStrip<Item: Hashable>: View {

    let segments: [WSegment<Item>]
    let selection: Binding<Item>
    let style: WSegmentedSwitcherStyle

    /// Seeded once. Survives parent re-renders, so a drag in flight is never
    /// interrupted by an unrelated update upstream.
    @StateObject private var model: WSegmentedSwitcherModel<Item>

    init(segments: [WSegment<Item>], selection: Binding<Item>, style: WSegmentedSwitcherStyle) {
        self.segments = segments
        self.selection = selection
        self.style = style
        _model = StateObject(wrappedValue: WSegmentedSwitcherModel(selection: selection.wrappedValue))
    }

    var body: some View {
        SegmentedStrip(segments: segments, model: model, style: style)
            .onChange(of: model.selection) { _, new in
                guard selection.wrappedValue != new else { return }
                selection.wrappedValue = new
            }
            .onChange(of: selection.wrappedValue) { _, new in
                model.set(new)
            }
    }
}

// MARK: - The strip itself

private struct SegmentedStrip<Item: Hashable>: View {

    let segments: [WSegment<Item>]
    @ObservedObject var model: WSegmentedSwitcherModel<Item>
    let style: WSegmentedSwitcherStyle

    private var items: [Item] { segments.map(\.id) }

    var body: some View {
        VStack(spacing: style.indicatorSpacing) {
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    label(for: segment)
                }
            }
            .padding(.horizontal, style.horizontalPadding)

            indicatorBar
        }
        .background(style.background)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { model.segmentWidth = segmentWidth(in: geo.size.width) }
                    .onChange(of: geo.size.width) { _, width in
                        model.segmentWidth = segmentWidth(in: width)
                    }
            }
        )
        .wSegmentedSwipe(model, items: items)
    }

    private func segmentWidth(in total: CGFloat) -> CGFloat {
        let usable = total - (style.horizontalPadding * 2)
        return usable / CGFloat(max(segments.count, 1))
    }

    @ViewBuilder
    private func label(for segment: WSegment<Item>) -> some View {
        let emphasis = self.emphasis(for: segment.id)

        Text(segment.title)
            .font(emphasis > 0.5 ? (style.selectedFont ?? style.font) : style.font)
            .foregroundColor(
                style.unselectedColor.blended(to: style.selectedColor, amount: emphasis)
            )
            .scaleEffect(1 + ((style.selectedScale - 1) * emphasis))
            .tracking(style.tracking)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, style.verticalPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                model.prepareHaptics()
                model.select(segment.id)
            }
    }

    @ViewBuilder
    private var indicatorBar: some View {
        switch style.indicator {
        case .none:
            EmptyView()
        case let .underline(height, cornerRadius, inset):
            GeometryReader { geo in
                let width = segmentWidth(in: geo.size.width)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(style.indicatorColor)
                    .frame(width: max(width - (inset * 2), 0), height: height)
                    .offset(x: (indicatorSlot * width) + inset)
            }
            .frame(height: height)
            .padding(.horizontal, style.horizontalPadding)
            .animation(WSegmentedSwitcherModel<Item>.settleAnimation, value: indicatorSlot)
        }
    }

    /// Fractional slot position, so the underline glides *with* the finger
    /// rather than jumping once the drag commits.
    private var indicatorSlot: CGFloat {
        guard let current = items.firstIndex(of: model.selection) else { return 0 }
        let direction = CGFloat(model.dragDirection(in: items))
        return CGFloat(current) + (direction * model.dragProgress())
    }

    /// The selected label sheds emphasis as the finger pulls toward a neighbour
    /// and that neighbour picks it up, so the two cross-fade mid-drag.
    private func emphasis(for item: Item) -> CGFloat {
        guard let selected = items.firstIndex(of: model.selection),
              let index = items.firstIndex(of: item) else { return 0 }

        let direction = model.dragDirection(in: items)
        let progress = model.dragProgress()

        if index == selected {
            return direction == 0 ? 1 : 1 - progress
        }
        if direction != 0, index == selected + direction {
            return progress
        }
        return 0
    }
}

// MARK: - Colour blending

private extension Color {
    /// Linear blend, for drag-tracked emphasis.
    func blended(to other: Color, amount: CGFloat) -> Color {
        let t = min(max(amount, 0), 1)
        guard t > 0 else { return self }
        guard t < 1 else { return other }

        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        UIColor(self).getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        UIColor(other).getRed(&tr, green: &tg, blue: &tb, alpha: &ta)

        return Color(
            red:   Double(fr + (tr - fr) * t),
            green: Double(fg + (tg - fg) * t),
            blue:  Double(fb + (tb - fb) * t),
            opacity: Double(fa + (ta - fa) * t)
        )
    }
}
