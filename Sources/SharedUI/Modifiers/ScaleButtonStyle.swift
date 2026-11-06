// MARK: - SharedUI/Modifiers/ScaleButtonStyle.swift

import SwiftUI

public struct ScaleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.22), value: configuration.isPressed)
    }
}
