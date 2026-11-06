import SwiftUI
import WaanguSharedUI

enum ChatBubbleStyle {
    static func background(for direction: MessageDirection) -> Color {
        direction == .sent
            ? Color("bubbleSent", bundle: .nativeUi)
            : Color("bubbleReceived", bundle: .nativeUi)
    }

    static func foreground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : Color(.label)
    }

    static func secondaryForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color(.secondaryLabel)
    }

    static func mutedOverlay(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    /// The brand accent for interactive marks inside a bubble — a chosen poll
    /// option, its result bar, a call to action.
    ///
    /// These are the exact values of the `AppPrimary` colorset, written as hex
    /// rather than read from the asset catalog: `Color("AppPrimary")` resolves to
    /// nothing from inside this package, and a colour that fails to resolve does
    /// not fall back or warn — it draws clear, so the mark simply vanishes.
    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(hex: "#005BF3")
            : Color(hex: "#0274FD")
    }
}
