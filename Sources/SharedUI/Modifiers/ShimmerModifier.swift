// MARK: - SharedUI/Modifiers/ShimmerModifier.swift

import SwiftUI

public struct ShimmerModifier: ViewModifier {
    public let phase: CGFloat

    public init(phase: CGFloat) {
        self.phase = phase
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear,              location: phase - 0.25),
                            .init(color: .white.opacity(0.6), location: phase),
                            .init(color: .clear,              location: phase + 0.25),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 3)
                    .offset(x: -geo.size.width)
                }
                .allowsHitTesting(false)
                .clipped()
            )
    }
}
