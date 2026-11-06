//
//  CallControlButton.swift
//  FeatureChat
//
//  The single circular control used across every call surface.
//
//  One component covers all three appearances seen in the call UI:
//  a labelled button in the audio-call grid, a compact unlabelled button in the
//  video-call pill, and the red destructive end/decline button.
//

import SwiftUI

struct CallControlButton: View {

    enum Style {
        /// Labelled, 64pt — the audio call 2x3 panel.
        case grid
        /// Unlabelled, 56pt — the video call bottom pill.
        case pill

        var diameter: CGFloat {
            switch self {
            case .grid: return CallTheme.Metric.gridControlDiameter
            case .pill: return CallTheme.Metric.pillControlDiameter
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .grid: return 24
            case .pill: return 22
            }
        }

        var showsLabel: Bool {
            switch self {
            case .grid: return true
            case .pill: return false
            }
        }
    }

    enum Role {
        /// Toggles between idle (translucent) and active (solid white).
        case standard
        /// Always red — end call, decline.
        case destructive
    }

    let icon: String
    var label: String = ""
    var style: Style = .grid
    var role: Role = .standard
    var isActive: Bool = false
    /// Dims and disables the control without changing its footprint.
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(fillColor)
                        .frame(width: style.diameter, height: style.diameter)

                    Image(systemName: icon)
                        .font(.system(size: style.iconSize, weight: .medium))
                        .foregroundStyle(iconColor)
                        .contentTransition(.symbolEffect(.replace))
                }

                if style.showsLabel && !label.isEmpty {
                    Text(label)
                        .font(CallTheme.TextStyle.controlLabel)
                        .foregroundStyle(CallTheme.Palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .scaleEffect(isPressed ? 0.92 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        .animation(CallTheme.Motion.controlsFade, value: isActive)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Appearance

    private var fillColor: Color {
        switch role {
        case .destructive:
            return CallTheme.Palette.endCall
        case .standard:
            return isActive ? CallTheme.Palette.controlActive : CallTheme.Palette.controlIdle
        }
    }

    private var iconColor: Color {
        switch role {
        case .destructive:
            return .white
        case .standard:
            return isActive ? CallTheme.Palette.controlIconActive : CallTheme.Palette.controlIconIdle
        }
    }

    private var accessibilityText: String {
        label.isEmpty ? icon : label
    }
}
