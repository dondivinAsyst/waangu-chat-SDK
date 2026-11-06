import SwiftUI

// MARK: - Item

/// One tab. `id` is whatever the caller selects on; `systemImage` is an optional
/// SF Symbol name.
public struct WTabItem<Item: Hashable>: Identifiable {
    public let id: Item
    public let title: String
    public let systemImage: String?

    public init(id: Item, title: String, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

// MARK: - Style

public struct WTabStripStyle {

    public enum Layout {
        /// Every tab gets the same width. Fills the container.
        case equalWidth
        /// Tabs size to their content, left-aligned behind a trailing spacer.
        case intrinsic
        /// Tabs size to their content inside a horizontal scroll view, and the
        /// selected tab is scrolled to centre.
        case scrolling
    }

    public enum IconPlacement {
        case leading
        case above
    }

    public enum Indicator {
        case none
        /// A bar under each tab, spanning that tab's width.
        case underline(height: CGFloat)
        /// A filled capsule behind the selected tab.
        case capsule(selectedFill: Color)
    }

    public var font: Font
    public var selectedFont: Font?
    public var selectedColor: Color
    public var unselectedColor: Color
    public var indicatorColor: Color
    public var iconFont: Font
    public var iconPlacement: IconPlacement
    public var iconSpacing: CGFloat
    public var layout: Layout
    public var indicator: Indicator
    public var itemSpacing: CGFloat
    public var itemHorizontalPadding: CGFloat
    public var itemVerticalPadding: CGFloat
    public var contentHorizontalPadding: CGFloat

    public init(
        font: Font = .system(size: 14, weight: .regular),
        selectedFont: Font? = nil,
        selectedColor: Color,
        unselectedColor: Color,
        indicatorColor: Color? = nil,
        iconFont: Font = .system(size: 12),
        iconPlacement: IconPlacement = .leading,
        iconSpacing: CGFloat = 6,
        layout: Layout = .intrinsic,
        indicator: Indicator = .none,
        itemSpacing: CGFloat = 0,
        itemHorizontalPadding: CGFloat = 0,
        itemVerticalPadding: CGFloat = 0,
        contentHorizontalPadding: CGFloat = 0
    ) {
        self.font = font
        self.selectedFont = selectedFont
        self.selectedColor = selectedColor
        self.unselectedColor = unselectedColor
        self.indicatorColor = indicatorColor ?? selectedColor
        self.iconFont = iconFont
        self.iconPlacement = iconPlacement
        self.iconSpacing = iconSpacing
        self.layout = layout
        self.indicator = indicator
        self.itemSpacing = itemSpacing
        self.itemHorizontalPadding = itemHorizontalPadding
        self.itemVerticalPadding = itemVerticalPadding
        self.contentHorizontalPadding = contentHorizontalPadding
    }
}

public extension WTabStripStyle {

    /// Scrolling strip with a per-tab underline and leading icons.
    static func scrollingUnderline(
        tint: Color,
        unselected: Color,
        contentHorizontalPadding: CGFloat = 20
    ) -> Self {
        .init(
            font: .system(size: 14, weight: .regular),
            selectedFont: .system(size: 14, weight: .semibold),
            selectedColor: tint,
            unselectedColor: unselected,
            layout: .scrolling,
            indicator: .underline(height: 3),
            itemSpacing: 24,
            itemVerticalPadding: 14,
            contentHorizontalPadding: contentHorizontalPadding
        )
    }

    /// Equal-width strip with the icon stacked above the label.
    static func iconAbove(
        tint: Color,
        unselected: Color = .gray,
        iconSize: CGFloat = 23
    ) -> Self {
        .init(
            font: .caption,
            selectedColor: tint,
            unselectedColor: unselected,
            iconFont: .system(size: iconSize, weight: .medium),
            iconPlacement: .above,
            iconSpacing: 4,
            layout: .equalWidth
        )
    }

    /// Intrinsic-width capsule chips.
    static func chips(
        tint: Color,
        selectedFill: Color,
        unselected: Color = .gray
    ) -> Self {
        .init(
            font: .system(size: 15, weight: .semibold),
            selectedColor: tint,
            unselectedColor: unselected,
            layout: .intrinsic,
            indicator: .capsule(selectedFill: selectedFill),
            itemSpacing: 8,
            itemHorizontalPadding: 14,
            itemVerticalPadding: 7
        )
    }
}

// MARK: - Strip

/// A tab strip for the cases `WSegmentedSwitcher` deliberately does not cover:
/// tabs that size to their content, carry icons, or need to scroll.
///
/// Selection is tap-driven — there is no swipe, because a scrolling strip's
/// horizontal drag already belongs to the scroll view.
public struct WTabStrip<Item: Hashable>: View {

    private let items: [WTabItem<Item>]
    private let style: WTabStripStyle
    @Binding private var selection: Item

    private let haptics = SelectionHaptics()

    public init(
        items: [WTabItem<Item>],
        selection: Binding<Item>,
        style: WTabStripStyle
    ) {
        self.items = items
        self._selection = selection
        self.style = style
    }

    public var body: some View {
        switch style.layout {
        case .equalWidth:
            row(equalWidth: true)
                .padding(.horizontal, style.contentHorizontalPadding)
        case .intrinsic:
            HStack(spacing: style.itemSpacing) {
                ForEach(items) { item in
                    tab(item, equalWidth: false)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, style.contentHorizontalPadding)
        case .scrolling:
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    row(equalWidth: false)
                        .padding(.horizontal, style.contentHorizontalPadding)
                }
                .onChange(of: selection) { _, new in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(equalWidth: Bool) -> some View {
        HStack(spacing: style.itemSpacing) {
            ForEach(items) { item in
                tab(item, equalWidth: equalWidth)
            }
        }
    }

    @ViewBuilder
    private func tab(_ item: WTabItem<Item>, equalWidth: Bool) -> some View {
        let isSelected = item.id == selection

        VStack(spacing: 0) {
            content(for: item, isSelected: isSelected)
                .padding(.horizontal, style.itemHorizontalPadding)
                .padding(.vertical, style.itemVerticalPadding)
                .background(capsuleBackground(isSelected: isSelected))

            underline(isSelected: isSelected)
        }
        .frame(maxWidth: equalWidth ? .infinity : nil)
        .contentShape(Rectangle())
        .id(item.id)
        .onTapGesture { select(item.id) }
        // Un `onTapGesture` sur une vue ordinaire n'a aucun trait
        // d'accessibilité : VoiceOver annonçait ces onglets comme du texte, et
        // rien ne disait qu'ils étaient actionnables ni lequel était choisi.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // Identifiant dérivé de la valeur, pas du libellé : le libellé est
        // traduit, et un test qui chercherait « Waangu » échouerait dès qu'on
        // change de langue.
        .accessibilityIdentifier("tab_" + String(describing: item.id))
    }

    @ViewBuilder
    private func content(for item: WTabItem<Item>, isSelected: Bool) -> some View {
        let tint = isSelected ? style.selectedColor : style.unselectedColor
        let font = isSelected ? (style.selectedFont ?? style.font) : style.font

        Group {
            switch style.iconPlacement {
            case .leading:
                HStack(spacing: style.iconSpacing) {
                    icon(for: item)
                    Text(item.title).font(font)
                }
            case .above:
                VStack(spacing: style.iconSpacing) {
                    icon(for: item)
                    Text(item.title).font(font)
                }
            }
        }
        .foregroundColor(tint)
    }

    @ViewBuilder
    private func icon(for item: WTabItem<Item>) -> some View {
        if let systemImage = item.systemImage {
            Image(systemName: systemImage).font(style.iconFont)
        }
    }

    @ViewBuilder
    private func capsuleBackground(isSelected: Bool) -> some View {
        if case let .capsule(fill) = style.indicator {
            Capsule().fill(isSelected ? fill : Color.clear)
        }
    }

    @ViewBuilder
    private func underline(isSelected: Bool) -> some View {
        if case let .underline(height) = style.indicator {
            Rectangle()
                .fill(isSelected ? style.indicatorColor : Color.clear)
                .frame(height: height)
        }
    }

    private func select(_ item: Item) {
        guard item != selection else { return }
        haptics.changed()
        withAnimation(.easeInOut(duration: 0.2)) {
            selection = item
        }
    }
}
