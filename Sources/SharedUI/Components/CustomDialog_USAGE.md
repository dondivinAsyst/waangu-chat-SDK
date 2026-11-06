# CustomDialog Usage Guide

## Overview

`CustomDialog` is a fully customizable dialog system that replaces SwiftUI's limited `.confirmationDialog()` and `.alert()` modifiers. It provides complete control over animations, styling, and button configurations.

## Features

✅ **Full Animation Control** - Choose from multiple animation styles (scale, slide, fade, bouncy, smooth)  
✅ **Custom Styling** - Standard, destructive, success, and warning styles  
✅ **Flexible Buttons** - Multiple buttons with different roles and colors  
✅ **Spring Animations** - Configurable spring response and damping  
✅ **Dark Mode Support** - Automatically adapts to light/dark mode  
✅ **Easy Integration** - Simple view modifiers for quick implementation  

---

## Basic Usage

### 1. Simple Confirmation Dialog

```swift
import SharedUI

struct MyView: View {
    @State private var showDialog = false
    
    var body: some View {
        Button("Delete Item") {
            showDialog = true
        }
        .customConfirmationDialog(
            title: "Delete Item",
            message: "Are you sure you want to delete this item?",
            isPresented: $showDialog,
            destructiveTitle: "Delete",
            cancelTitle: "Cancel",
            animation: .spring,
            onConfirm: {
                // Handle deletion
                print("Item deleted")
            }
        )
    }
}
```

### 2. Simple Alert

```swift
struct MyView: View {
    @State private var showAlert = false
    @State private var errorMessage: String?
    
    var body: some View {
        Button("Show Error") {
            errorMessage = "Something went wrong!"
            showAlert = true
        }
        .customAlert(
            title: "Error",
            message: errorMessage,
            isPresented: $showAlert,
            okTitle: "OK",
            animation: .smooth,
            onDismiss: {
                errorMessage = nil
            }
        )
    }
}
```

---

## Advanced Usage

### 3. Custom Dialog with Multiple Buttons

```swift
struct MyView: View {
    @State private var showDialog = false
    
    var body: some View {
        Button("Show Options") {
            showDialog = true
        }
        .customDialog(
            isPresented: $showDialog,
            configuration: DialogConfiguration(
                title: "Choose Action",
                message: "What would you like to do?",
                style: .standard,
                buttons: [
                    DialogButton(title: "Save", role: .primary) {
                        print("Saved")
                    },
                    DialogButton(title: "Delete", role: .destructive) {
                        print("Deleted")
                    },
                    DialogButton(title: "Cancel", role: .cancel) {
                        print("Cancelled")
                    }
                ],
                animation: .bouncy
            )
        )
    }
}
```

### 4. Block/Unblock Contact Example (Real-world)

```swift
struct ContactView: View {
    @State private var showBlockDialog = false
    @State private var isBlocked = false
    
    var body: some View {
        Button(isBlocked ? "Unblock" : "Block") {
            showBlockDialog = true
        }
        .customDialog(
            isPresented: $showBlockDialog,
            configuration: DialogConfiguration(
                title: isBlocked ? "Unblock Contact" : "Block Contact",
                message: "Do you really want to \(isBlocked ? "unblock" : "block") this contact?",
                style: isBlocked ? .standard : .destructive,
                buttons: [
                    DialogButton(
                        title: isBlocked ? "Unblock" : "Block",
                        role: isBlocked ? .primary : .destructive
                    ) {
                        Task {
                            await toggleBlockStatus()
                        }
                    },
                    DialogButton(title: "Cancel", role: .cancel) {}
                ],
                animation: .bouncy
            )
        )
    }
    
    func toggleBlockStatus() async {
        isBlocked.toggle()
    }
}
```

---

## Animation Styles

### Available Animations

```swift
// Default scale animation
.animation: .default

// Spring animation (bouncy)
.animation: .spring

// Smooth animation
.animation: .smooth

// Extra bouncy
.animation: .bouncy

// Slide up from bottom
.animation: .slideUp

// Fade in/out
.animation: .fade
```

### Custom Animation

```swift
DialogAnimation(
    entrance: .scale,
    exit: .slideDown,
    duration: 0.4,
    springResponse: 0.5,
    springDamping: 0.7
)
```

---

## Dialog Styles

### Standard
```swift
style: .standard
```
- Default appearance
- No icon
- Primary text color

### Destructive
```swift
style: .destructive
```
- Red title color
- Warning triangle icon
- Used for delete/block actions

### Success
```swift
style: .success
```
- Green title color
- Checkmark circle icon
- Used for confirmations

### Warning
```swift
style: .warning
```
- Orange title color
- Exclamation circle icon
- Used for warnings

---

## Button Roles

### Standard
```swift
role: .standard
```
- Default appearance
- Card background
- Border outline

### Primary
```swift
role: .primary
```
- Brand primary color background
- White text
- No border

### Destructive
```swift
role: .destructive
```
- Red background
- White text
- Used for dangerous actions

### Cancel
```swift
role: .cancel
```
- Card background
- Border outline
- Dismisses dialog

---

## Complete Example

Here's the ContactProfileView implementation:

```swift
import SwiftUI
import SharedUI

struct ContactProfileView: View {
    @State private var showClearChatConfirmation = false
    @State private var showBlockConfirmation = false
    @State private var clearChatError: String?
    @State private var blockError: String?
    @StateObject private var viewModel: ContactProfileViewModel
    
    var body: some View {
        VStack {
            // Your UI here
            
            Button("Clear Chat") {
                showClearChatConfirmation = true
            }
            
            Button("Block Contact") {
                showBlockConfirmation = true
            }
        }
        // Clear Chat Dialog
        .customDialog(
            isPresented: $showClearChatConfirmation,
            configuration: DialogConfiguration(
                title: "Clear Chat",
                message: "Clear all messages in this chat on this device? This action cannot be undone.",
                style: .destructive,
                buttons: [
                    DialogButton(title: "Clear chat", role: .destructive) {
                        do {
                            try clearChat()
                        } catch {
                            clearChatError = error.localizedDescription
                        }
                    },
                    DialogButton(title: "Cancel", role: .cancel) {}
                ],
                animation: .spring
            )
        )
        // Block Contact Dialog
        .customDialog(
            isPresented: $showBlockConfirmation,
            configuration: DialogConfiguration(
                title: viewModel.user?.isBlocked == true ? "Unblock Contact" : "Block Contact",
                message: "Do you really want to \(viewModel.user?.isBlocked == true ? "unblock" : "block") \(viewModel.user?.name ?? "this contact")?",
                style: viewModel.user?.isBlocked == true ? .standard : .destructive,
                buttons: [
                    DialogButton(
                        title: viewModel.user?.isBlocked == true ? "Unblock" : "Block",
                        role: viewModel.user?.isBlocked == true ? .primary : .destructive
                    ) {
                        Task {
                            await viewModel.toggleBlockContact()
                        }
                    },
                    DialogButton(title: "Cancel", role: .cancel) {}
                ],
                animation: .bouncy
            )
        )
        // Error Alerts
        .customAlert(
            title: "Could not clear chat",
            message: clearChatError,
            isPresented: .init(
                get: { clearChatError != nil },
                set: { if !$0 { clearChatError = nil } }
            ),
            okTitle: "OK",
            animation: .smooth,
            onDismiss: { clearChatError = nil }
        )
        .customAlert(
            title: "Block Error",
            message: blockError,
            isPresented: .init(
                get: { blockError != nil },
                set: { if !$0 { blockError = nil } }
            ),
            okTitle: "OK",
            animation: .smooth,
            onDismiss: { blockError = nil }
        )
    }
    
    func clearChat() throws {
        // Implementation
    }
}
```

---

## Migration Guide

### Before (SwiftUI's confirmationDialog)

```swift
.confirmationDialog(
    "Clear all messages?",
    isPresented: $showDialog,
    titleVisibility: .visible
) {
    Button("Clear", role: .destructive) {
        clearMessages()
    }
    Button("Cancel", role: .cancel) {}
}
```

### After (CustomDialog)

```swift
.customConfirmationDialog(
    title: "Clear all messages?",
    message: "This action cannot be undone.",
    isPresented: $showDialog,
    destructiveTitle: "Clear",
    cancelTitle: "Cancel",
    animation: .spring,
    onConfirm: {
        clearMessages()
    }
)
```

---

## Benefits Over Native Dialogs

| Feature | Native `.confirmationDialog` | `CustomDialog` |
|---------|------------------------------|----------------|
| Animation Control | ❌ Limited | ✅ Full control |
| Custom Styling | ❌ System only | ✅ Fully customizable |
| Multiple Button Styles | ❌ Limited | ✅ 4 button roles |
| Spring Animations | ❌ No | ✅ Yes |
| Icons | ❌ No | ✅ Yes |
| Dark Mode | ✅ Yes | ✅ Yes |
| Custom Colors | ❌ No | ✅ Yes |

---

## Tips & Best Practices

1. **Use appropriate animations**: 
   - `.spring` or `.bouncy` for confirmation dialogs
   - `.smooth` for alerts
   - `.slideUp` for bottom sheets

2. **Match style to action**:
   - `.destructive` for delete/block actions
   - `.success` for confirmations
   - `.warning` for cautions
   - `.standard` for general dialogs

3. **Keep messages concise**: Short, clear messages work best

4. **Use proper button roles**:
   - Primary action → `.primary`
   - Dangerous action → `.destructive`
   - Dismiss → `.cancel`

5. **Handle errors gracefully**: Use `.customAlert()` for error messages

---

## API Reference

### DialogConfiguration

```swift
DialogConfiguration(
    title: String,              // Dialog title
    message: String? = nil,     // Optional message
    style: DialogStyle,         // .standard, .destructive, .success, .warning
    buttons: [DialogButton],    // Array of buttons
    animation: DialogAnimation  // Animation configuration
)
```

### DialogButton

```swift
DialogButton(
    title: String,              // Button text
    role: ButtonRole,           // .standard, .primary, .destructive, .cancel
    action: @escaping () -> Void // Button action
)
```

### DialogAnimation

```swift
DialogAnimation(
    entrance: AnimationType,    // .scale, .slideUp, .slideDown, .fade, .scaleAndSlide
    exit: AnimationType,        // Same as entrance
    duration: Double,           // Animation duration
    springResponse: Double,     // Spring response (0.3-0.6)
    springDamping: Double       // Spring damping (0.6-0.9)
)
```

---

## Support

For issues or questions, refer to the SharedUI documentation or contact the development team.
