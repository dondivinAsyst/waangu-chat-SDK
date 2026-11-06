# BrandedToggle Usage Guide

## Overview
`BrandedToggle` is a reusable SwiftUI toggle component that automatically applies the app's primary brand color (`AppColors.primary`). This ensures consistent styling across the application and makes it easy to maintain a unified brand identity.

## Features
- ✅ Automatically uses `AppColors.primary` for tint color
- ✅ Supports simple text labels
- ✅ Supports complex custom labels with icons and subtitles
- ✅ Works with SwiftUI's `.tint()` modifier under the hood
- ✅ Fully compatible with dark mode
- ✅ Integrates seamlessly with SwiftUI Lists and Forms

## Import
```swift
import SharedUI
```

## Basic Usage

### Simple Text Label
```swift
@State private var isEnabled = false

BrandedToggle("Enable Notifications", isOn: $isEnabled)
```

### With Icon Label
```swift
BrandedToggle(isOn: $isMuted) {
    Label("Mute notifications", systemImage: "bell.slash")
}
```

### With Subtitle
```swift
BrandedToggle(isOn: $lockChatEnabled) {
    VStack(alignment: .leading, spacing: 4) {
        Text("Lock chat")
            .font(.subheadline)
        Text("Require authentication to open this chat")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

## Migration from Standard Toggle

### Before (Standard Toggle)
```swift
Toggle(isOn: $isMuted) {
    Label("Mute notifications", systemImage: "bell.slash")
}
// No brand color applied - uses system default
```

### After (BrandedToggle)
```swift
BrandedToggle(isOn: $isMuted) {
    Label("Mute notifications", systemImage: "bell.slash")
}
// Automatically uses AppColors.primary
```

## Common Patterns

### In a List
```swift
List {
    Section {
        BrandedToggle("Save to Photos", isOn: $saveToPhotosEnabled)
        BrandedToggle("Lock Chat", isOn: $lockChatEnabled)
        BrandedToggle("Advanced Privacy", isOn: $advancedPrivacyEnabled)
    } header: {
        Text("Settings")
    }
}
```

### With Binding and Callback
```swift
BrandedToggle(
    isOn: Binding(
        get: { viewModel.isMuted },
        set: { newValue in
            Task { @MainActor in
                try? viewModel.setMuted(newValue)
            }
        }
    )
) {
    Label("Mute notifications", systemImage: "bell.slash")
}
```

### In Group Permissions
```swift
BrandedToggle(isOn: $settings.onlyAdminsCanSend) {
    VStack(alignment: .leading, spacing: 4) {
        Text("Only admins can send messages")
            .font(.subheadline)
        Text("When enabled, only admins can send messages in this group")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

## Advantages Over Standard Toggle

1. **Consistency**: All toggles across the app automatically use the brand color
2. **Maintainability**: If the brand color changes, update `AppColors.swift` once
3. **Simplicity**: No need to remember to add `.tint(AppColors.primary)` everywhere
4. **Less Code**: Cleaner, more declarative code
5. **Type Safety**: Leverages Swift's type system for better compile-time checks

## When to Use

Use `BrandedToggle` for:
- ✅ Settings screens
- ✅ Preference toggles
- ✅ Feature enable/disable switches
- ✅ Permission controls
- ✅ Any toggle that should reflect the app's branding

Use standard `Toggle` only when:
- ❌ You specifically need a different color (rare)
- ❌ You're working with system-level settings that shouldn't be branded

## Color Behavior

The toggle uses `AppColors.primary`:
- **Light Mode**: `#08569E` (dark blue)
- **Dark Mode**: `#1A6BB5` (lighter blue)

The color automatically adapts based on the user's system appearance.

## Examples in the App

### Group Settings (GroupInfoView)
```swift
BrandedToggle(
    isOn: Binding(
        get: { viewModel.isMuted },
        set: { newValue in
            Task { @MainActor in
                try? viewModel.setMuted(newValue)
                viewModel.reloadMuteFromStore()
            }
        }
    )
) {
    Label("Mute notifications", systemImage: "bell.slash")
}
```

### Group Permissions (GroupPermissionsSheet)
```swift
BrandedToggle(isOn: $settings.onlyAdminsCanSend) {
    VStack(alignment: .leading, spacing: 4) {
        Text("Only admins can send messages")
            .font(.subheadline)
        Text("When enabled, only admins can send messages in this group")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

### Local Settings (GroupInfoView)
```swift
BrandedToggle(
    isOn: Binding(
        get: { lockChatEnabled },
        set: { newValue in
            lockChatEnabled = newValue
            viewModel.persistLocalBoolSetting(key: "lockChat", value: newValue)
        }
    )
) {
    Label("Lock chat", systemImage: "lock")
}
```

## API Reference

### Initializers

#### init(_:isOn:)
```swift
public init(_ title: String, isOn: Binding<Bool>)
```
Creates a branded toggle with a simple text label.

**Parameters:**
- `title`: The text to display as the label
- `isOn`: Binding to the toggle state

#### init(isOn:label:)
```swift
public init<Label: View>(isOn: Binding<Bool>, @ViewBuilder label: () -> Label)
```
Creates a branded toggle with a custom label.

**Parameters:**
- `isOn`: Binding to the toggle state
- `label`: A view builder that creates the toggle label

## Related Components

- `AppColors` - Defines the brand colors used by BrandedToggle
- `CustomDialog` - For confirmation dialogs
- `WPrimaryButton` - For branded buttons

## Notes

- The component is marked `public` and can be used across all app modules
- The preview includes both light and dark mode examples
- The component works with all standard SwiftUI modifiers
