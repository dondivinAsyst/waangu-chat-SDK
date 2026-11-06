//
//  CallTopBar.swift
//  FeatureChat
//
//  Header shared by the connected audio and video call screens: minimise on the
//  leading edge, participant identity in the centre, and the stacked
//  add-participant / in-call-chat actions on the trailing edge.
//
//  Flip-camera appears in that trailing stack only while the local feed is the
//  main stage (swapped / ringing), so it never covers Open chat.
//

import SwiftUI

struct CallTopBar: View {

    let title: String
    let subtitle: String
    var onMinimize: () -> Void
    var onAddParticipant: () -> Void
    var onOpenChat: () -> Void
    /// Shown when the local camera fills the main stage.
    var showsFlipCamera: Bool = false
    var onFlipCamera: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            circleButton(icon: "arrow.down.right.and.arrow.up.left", action: onMinimize)
                .accessibilityLabel(Text("Minimize call"))

            Spacer(minLength: 0)

            identity
                // Keeps the title optically centred against the taller trailing stack.
                .padding(.top, 2)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                circleButton(icon: "person.badge.plus", action: onAddParticipant)
                    .accessibilityLabel(Text("Add participant"))
                circleButton(icon: "message.fill", action: onOpenChat)
                    .accessibilityLabel(Text("Open chat"))

                if showsFlipCamera, let onFlipCamera {
                    circleButton(
                        icon: "arrow.triangle.2.circlepath.camera",
                        action: onFlipCamera
                    )
                    .accessibilityLabel(Text("Flip camera"))
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.85, anchor: .top))
                    )
                }
            }
            .animation(CallTheme.Motion.controlsFade, value: showsFlipCamera)
        }
        .padding(.horizontal, 16)
    }

    private var identity: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(CallTheme.TextStyle.connectedName)
                .foregroundStyle(CallTheme.Palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(CallTheme.TextStyle.duration)
                .foregroundStyle(CallTheme.Palette.secondaryText)
        }
        .frame(maxWidth: 200)
    }

    private func circleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.13))
                    .frame(
                        width: CallTheme.Metric.topBarControlDiameter,
                        height: CallTheme.Metric.topBarControlDiameter
                    )
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}
