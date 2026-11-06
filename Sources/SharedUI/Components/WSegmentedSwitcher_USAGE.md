# WSegmentedSwitcher

A segmented switcher whose labels track the finger, whose indicator glides, and
whose selection snaps with a haptic.

Use it for **equal-width text segments**. It is not a scrollable tab bar, and it
does not do icons — see "When not to use this" below.

## Standalone (taps + drag on the strip)

```swift
@State private var tab: MyTab = .first

WSegmentedSwitcher(
    segments: MyTab.allCases.map { WSegment(id: $0, title: $0.title) },
    selection: $tab,
    style: .underline(tint: AppColors.primary)
)
```

The switcher owns its drag state internally and mirrors the selection back into
your `Binding`. Nothing else is needed at the call site.

## With a swipeable content area

Share one model between the strip and the content so a swipe over the content
moves the strip:

```swift
@StateObject private var switcher = WSegmentedSwitcherModel(selection: MyTab.first)

VStack(spacing: 0) {
    content
        .wSegmentedSwipe(switcher, items: MyTab.allCases)

    WSegmentedSwitcher(
        segments: MyTab.allCases.map { WSegment(id: $0, title: $0.title) },
        model: switcher,
        style: .composer
    )
}
.onAppear {
    switcher.onChange = { tab in /* react to a user-driven change */ }
}
```

Read the current value from `switcher.selection`.

## Styles

| Style | Look |
|---|---|
| `.composer` | Dark bar, amber selected label, no indicator, scale on select |
| `.underline(tint:)` | Gliding underline, weight change on select |
| `.plain(tint:)` | Labels only, no indicator |

`WSegmentedSwitcherStyle` is a plain struct — build one inline for a one-off
screen rather than adding a preset here. `selectedColor` (the label) and
`indicatorColor` (the underline) are separate, because several screens tint them
differently.

## Translations

`SharedUI` has no access to `CoreKit`, so the switcher takes **already-resolved**
title strings. Resolve them at the call site:

```swift
WSegment(id: EditorTab.video, title: t(ChatTranslationKeys.STORIES_VIDEO_LABEL))
```

## When not to use this

Segments are laid out at equal width, labels only, and the control assumes the
content behind it is pageable. Use **`WTabStrip`** instead when the strip needs to
scroll, size tabs to their content, or carry icons — see `WTabStrip_USAGE.md`.

## Notes

- `set(_:)` changes selection silently — use it for deep links and restored
  drafts. `select(_:)` is for user-driven changes and fires the haptic.
- Attach `.wSegmentedSwipe` to the **content**, not the strip; the strip already
  handles its own drag.
- Haptics are silent on the simulator. Verify the feel on a device.
