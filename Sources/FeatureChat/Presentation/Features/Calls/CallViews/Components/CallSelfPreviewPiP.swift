//
//  CallSelfPreviewPiP.swift
//  FeatureChat
//
//  The local camera picture-in-picture tile on a video call.
//
//  Drag it anywhere; on release it snaps to whichever corner it is closest to,
//  the way the system video-call PiP behaves. It shrinks and sheds its inline
//  controls when the call chrome is hidden, so it stays out of the way of the
//  remote feed.
//
//  The camera feed itself is injected as `content`, keeping this component free
//  of any capture-session dependency — it renders a placeholder until the video
//  pipeline supplies a real preview layer.
//

import SwiftUI

struct CallSelfPreviewPiP<Content: View>: View {

    enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }

        /// Unit position used to measure distance when picking the nearest corner.
        var unitPoint: CGPoint {
            switch self {
            case .topLeading: return CGPoint(x: 0, y: 0)
            case .topTrailing: return CGPoint(x: 1, y: 0)
            case .bottomLeading: return CGPoint(x: 0, y: 1)
            case .bottomTrailing: return CGPoint(x: 1, y: 1)
            }
        }
    }

    /// Collapses the tile and hides its inline controls — used when call chrome is hidden.
    var isCompact: Bool = false
    var showsInlineControls: Bool = true
    /// Fired on a light tap (not a drag). Used to swap primary ↔ PiP.
    var onTap: (() -> Void)? = nil
    var onFlipCamera: () -> Void = {}
    var onToggleEffects: () -> Void = {}
    @ViewBuilder var content: () -> Content

    @State private var corner: Corner = .bottomTrailing
    @State private var dragOffset: CGSize = .zero

    private var width: CGFloat {
        isCompact ? CallTheme.Metric.pipCompactWidth : CallTheme.Metric.pipWidth
    }

    private var height: CGFloat {
        isCompact ? CallTheme.Metric.pipCompactHeight : CallTheme.Metric.pipHeight
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: corner.alignment) {
                // Keep the layout container from stealing taps meant for chrome.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                tile
                    .frame(width: width, height: height)
                    .contentShape(RoundedRectangle(
                        cornerRadius: CallTheme.Metric.pipCornerRadius,
                        style: .continuous
                    ))
                    .offset(dragOffset)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                    // Tap for swap; drag only after a real move so avatar PiP stays tappable.
                    .gesture(dragGesture(in: geometry.size))
                    .simultaneousGesture(
                        TapGesture().onEnded { onTap?() }
                    )
                    .animation(CallTheme.Motion.pipSnap, value: corner)
                    .animation(CallTheme.Motion.pipSnap, value: isCompact)
            }
        }
        .accessibilityLabel(Text("Self preview"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onTap?()
        }
    }

    // MARK: - Tile

    private var tile: some View {
        ZStack(alignment: .topTrailing) {
            content()
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: CallTheme.Metric.pipCornerRadius, style: .continuous))
                // Avatar / waveform must not steal the tile's tap / drag.
                .allowsHitTesting(false)

            if showsInlineControls && !isCompact {
                inlineControls
                    .padding(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: CallTheme.Metric.pipCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    private var inlineControls: some View {
        VStack(spacing: 10) {
            inlineButton(icon: "arrow.triangle.2.circlepath.camera", action: onFlipCamera)
            inlineButton(icon: "sparkles", action: onToggleEffects)
        }
    }

    private func inlineButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dragging

    private func dragGesture(in containerSize: CGSize) -> some Gesture {
        // `minimumDistance` leaves short presses to `onTapGesture` for swap.
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let released = releasePoint(for: value, in: containerSize)
                withAnimation(CallTheme.Motion.pipSnap) {
                    corner = nearestCorner(to: released, in: containerSize)
                    dragOffset = .zero
                }
            }
    }

    /// Where the tile's centre ends up, accounting for flick momentum.
    private func releasePoint(for value: DragGesture.Value, in containerSize: CGSize) -> CGPoint {
        let anchor = currentCenter(in: containerSize)
        return CGPoint(
            x: anchor.x + value.predictedEndTranslation.width,
            y: anchor.y + value.predictedEndTranslation.height
        )
    }

    private func currentCenter(in containerSize: CGSize) -> CGPoint {
        let unit = corner.unitPoint
        let insetX = width / 2 + 14
        let insetY = height / 2 + 18
        return CGPoint(
            x: unit.x == 0 ? insetX : containerSize.width - insetX,
            y: unit.y == 0 ? insetY : containerSize.height - insetY
        )
    }

    private func nearestCorner(to point: CGPoint, in containerSize: CGSize) -> Corner {
        Corner.allCases.min(by: { lhs, rhs in
            distance(from: point, to: lhs, in: containerSize)
                < distance(from: point, to: rhs, in: containerSize)
        }) ?? .bottomTrailing
    }

    private func distance(from point: CGPoint, to corner: Corner, in containerSize: CGSize) -> CGFloat {
        let target = CGPoint(
            x: corner.unitPoint.x * containerSize.width,
            y: corner.unitPoint.y * containerSize.height
        )
        return hypot(point.x - target.x, point.y - target.y)
    }
}

// MARK: - Placeholder feed

/// Shown while capture is starting, or when camera access has been refused.
struct CallSelfPreviewPlaceholder: View {

    var icon: String = "video.fill"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.19, green: 0.19, blue: 0.21),
                    Color(red: 0.11, green: 0.11, blue: 0.13)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }
}
