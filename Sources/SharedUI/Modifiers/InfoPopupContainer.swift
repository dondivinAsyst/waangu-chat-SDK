// MARK: - SharedUI/Modifiers/InfoPopupContainer.swift

import SwiftUI

public struct InfoPopupContainerModifier: ViewModifier {

    @Binding public var show: Bool
    public let popup: InfoPopup

    public init(show: Binding<Bool>, popup: InfoPopup) {
        self._show = show
        self.popup = popup
    }

    public func body(content: Content) -> some View {
        ZStack {
            content

            if show {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                popup
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: show)
    }
}
