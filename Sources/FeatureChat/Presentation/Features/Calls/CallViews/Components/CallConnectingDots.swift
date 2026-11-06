//
//  CallConnectingDots.swift
//  FeatureChat
//
//  A row of dots that keeps moving while the call is waiting on somebody.
//
//  Shared rather than private to one screen: the outgoing 1:1 stage and the
//  waiting tiles in the participant grid are saying the same thing, and a
//  status line that never moves reads as a frozen call rather than a pending one.
//

import SwiftUI

struct CallConnectingDots: View {

    /// Bars sized for a grid tile need to be smaller than the ones on a
    /// full-screen stage, and the tint follows whichever surface hosts them.
    var dotSize: CGFloat = 5
    var spacing: CGFloat = 6
    var tint: Color = CallTheme.Palette.remoteName

    @State private var isAnimating = false
    private let dotCount = 6

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(tint)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(isAnimating ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.1),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
        .accessibilityHidden(true)
    }
}
