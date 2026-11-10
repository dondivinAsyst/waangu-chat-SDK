//
//  ChatHeroVisuals.swift
//  FeatureChat
//
//  The pieces the intro sheets, the communities empty state and the join
//  screen share, so the four read as one family.
//

import SwiftUI
import WaanguSharedUI

/// A solid rounded badge in the app blue with a white glyph.
///
/// Solid and lit rather than a pale disc with an outline icon: the gradient runs
/// from a lighter blue at the top to `AppColors.primary` at the bottom, a thin
/// highlight catches the top edge, and a soft blue shadow sits under it. One
/// hue only — the app's own.
@available(iOS 16.0, *)
struct ChatSymbolBadge: View {

    let symbol: String
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .symbolVariant(.fill)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [AppColors.centerGradientStart, AppColors.primary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: AppColors.primary.opacity(0.28), radius: size * 0.18, y: size * 0.1)
            .accessibilityHidden(true)
    }
}

/// The picture band at the top of an intro: a soft wash of the app blue, two
/// blurred blobs and a few small dots, with the subject's badge in the middle.
/// The blobs and dots drift in when it appears; with Reduce Motion they are
/// simply there.
@available(iOS 16.0, *)
struct ChatHeroBand: View {

    let symbol: String
    var height: CGFloat = 190
    var cornerRadius: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        ZStack {
            // Full-width (no corners): fades out completely, so the band melts into
            // the page instead of ending on a line. As a card it keeps a tint,
            // so its rounded shape still reads.
            LinearGradient(
                colors: [AppColors.primary.opacity(0.16),
                         AppColors.primary.opacity(cornerRadius == 0 ? 0 : 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(AppColors.primary.opacity(0.22))
                .frame(width: 150, height: 150)
                .blur(radius: 40)
                .offset(x: settled ? -90 : -60, y: settled ? -30 : -10)

            Circle()
                .fill(AppColors.centerGradientStart.opacity(0.20))
                .frame(width: 120, height: 120)
                .blur(radius: 36)
                .offset(x: settled ? 100 : 70, y: settled ? 40 : 20)

            ForEach(Self.dots.indices, id: \.self) { index in
                let dot = Self.dots[index]
                Circle()
                    .fill(AppColors.primary.opacity(dot.opacity))
                    .frame(width: dot.size, height: dot.size)
                    .offset(x: dot.x, y: settled ? dot.y : dot.y + 10)
                    .opacity(settled ? 1 : 0)
            }

            ChatSymbolBadge(symbol: symbol, size: 84)
                .rotationEffect(.degrees(settled ? -6 : 0))
                .scaleEffect(settled ? 1 : 0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .mask { bandMask }
        .onAppear {
            if reduceMotion {
                settled = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { settled = true }
            }
        }
    }

    /// As a card: its rounded shape. Full width: a soft fade at the bottom, so
    /// the blurred blobs do not end on a cut line.
    @ViewBuilder
    private var bandMask: some View {
        if cornerRadius > 0 {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        } else {
            LinearGradient(
                stops: [.init(color: .black, location: 0),
                        .init(color: .black, location: 0.6),
                        .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private struct Dot {
        let x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double
    }

    private static let dots: [Dot] = [
        Dot(x: -120, y: 50, size: 6, opacity: 0.35),
        Dot(x: -70, y: -60, size: 4, opacity: 0.30),
        Dot(x: 85, y: -55, size: 7, opacity: 0.30),
        Dot(x: 130, y: 10, size: 4, opacity: 0.40),
        Dot(x: 60, y: 65, size: 5, opacity: 0.25)
    ]
}

/// Brings a part of a screen in after the ones before it: a fade with a short
/// upward slide, `index` × 70 ms late. With Reduce Motion it only fades.
@available(iOS 16.0, *)
struct StaggeredAppear: ViewModifier {

    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(Double(index) * 0.07)) { shown = true }
            }
    }
}

@available(iOS 16.0, *)
extension View {
    func staggeredAppear(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}
