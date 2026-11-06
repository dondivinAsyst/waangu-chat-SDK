# WTabStrip

A tab strip for the cases `WSegmentedSwitcher` deliberately does not cover: tabs
that size to their content, carry icons, or need to scroll.

Selection is **tap-driven only**. There is no swipe, because a scrolling strip's
horizontal drag already belongs to its scroll view, and chips have no paged
content behind them to swipe through.

## Which component do I want?

| Need | Use |
|---|---|
| Equal-width text segments over pageable content | `WSegmentedSwitcher` |
| Icons, intrinsic widths, or horizontal scrolling | `WTabStrip` |

## Scrolling strip with underline

```swift
WTabStrip(
    items: BestPlansTab.allCases.map {
        WTabItem(id: $0, title: $0.rawValue, systemImage: $0.systemImage)
    },
    selection: $selectedTab,
    style: .scrollingUnderline(
        tint: AppColors.primary,
        unselected: AppColors.iconLabel.opacity(0.7)
    )
)
```

The selected tab is scrolled to centre automatically.

## Equal-width, icon above the label

```swift
WTabStrip(
    items: sheetTabItems,
    selection: $selectedTab,
    style: .iconAbove(tint: .blue)
)
```

## Capsule chips

```swift
WTabStrip(
    items: DestinationTab.allCases.map { WTabItem(id: $0, title: $0.rawValue) },
    selection: Binding(
        get: { viewModel.selectedTab },
        set: { viewModel.selectedTab = $0 }
    ),
    style: .chips(tint: Color(hex: "00691F"), selectedFill: Color(hex: "E6F4EA"))
)
```

## Styles

`WTabStripStyle` has three orthogonal axes, so build one inline rather than
adding a preset for a one-off screen:

- `layout`: `.equalWidth`, `.intrinsic` (left-aligned behind a spacer), `.scrolling`
- `iconPlacement`: `.leading`, `.above`
- `indicator`: `.none`, `.underline(height:)`, `.capsule(selectedFill:)`

Presets: `.scrollingUnderline(tint:unselected:)`, `.iconAbove(tint:)`,
`.chips(tint:selectedFill:)`.

## Translations

`SharedUI` has no access to `CoreKit`, so titles must be **already resolved**:

```swift
WTabItem(id: .gallery, title: t(ChatTranslationKeys.SHEET_MEDIA), systemImage: "photo.fill")
```

Build the item array at the call site rather than on the enum when the screen
offers only a subset of cases, or a specific order.

## Notes

- Every tap fires a prepared selection haptic. Silent on the simulator.
- `items` is an explicit array, not `allCases`, precisely so a screen can omit
  cases such as a `.unknown` placeholder.
