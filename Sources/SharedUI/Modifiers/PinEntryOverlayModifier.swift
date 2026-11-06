// MARK: - SharedUI/Modifiers/PinEntryOverlayModifier.swift

import SwiftUI

/// Presents a **bottom-sheet** numeric PIN panel (~half screen) on top of the host view, with a dimmed backdrop.
/// Tap outside the sheet to dismiss (same as the close control).
public struct PinEntryOverlayModifier: ViewModifier {

    @Binding public var show: Bool
    @Binding public var pin: String
    public let title: String
    public let digitCount: Int
    public let clearPinOnDismiss: Bool
    public let onComplete: (String) -> Void
    public let onDismiss: () -> Void

    /// Height of the PIN panel as a fraction of the available container (e.g. `0.55` ≈ half screen).
    public var sheetHeightFraction: CGFloat

    public init(
        show: Binding<Bool>,
        pin: Binding<String>,
        title: String,
        digitCount: Int,
        clearPinOnDismiss: Bool,
        onComplete: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void,
        sheetHeightFraction: CGFloat = 0.58
    ) {
        self._show = show
        self._pin = pin
        self.title = title
        self.digitCount = digitCount
        self.clearPinOnDismiss = clearPinOnDismiss
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        self.sheetHeightFraction = min(max(sheetHeightFraction, 0.4), 0.92)
    }

    public func body(content: Content) -> some View {
        ZStack {
            content

            if show {
                GeometryReader { geo in
                    let sheetH = geo.size.height * sheetHeightFraction

                    ZStack(alignment: .bottom) {
                        Color.black.opacity(0.38)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissPinSheet()
                            }
                            .transition(.opacity)

                        PinEntryOverlay(
                            title: title,
                            digitCount: digitCount,
                            pin: $pin,
                            onComplete: onComplete,
                            onDismiss: {
                                dismissPinSheet()
                            }
                        )
                        .frame(width: geo.size.width, height: sheetH, alignment: .top)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: -4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .ignoresSafeArea()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: show)
    }

    private func dismissPinSheet() {
        if clearPinOnDismiss {
            pin = ""
        }
        onDismiss()
        show = false
    }
}
