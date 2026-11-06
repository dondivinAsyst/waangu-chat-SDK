//
//  LiveLocationMarkerView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI

/// The person on the map during a live share.
///
/// A face rather than a pin, because a live share is about *who* is moving —
/// and in a group thread with two shares running, the pin alone says nothing
/// about which is which.
///
/// The halo is the liveness signal: it pulses only while the share is running,
/// so a finished share is a still face and the difference reads at a glance,
/// without waiting for a caption. Shared by the bubble's mini-map and the
/// full-screen viewer so a share opened from a bubble looks like the bubble it
/// came from.
struct LiveLocationMarkerView: View {

    let avatarURL: String?
    /// Used for the initials fallback when the sharer has no picture.
    let fallbackName: String
    /// Pulses while true; a still face once the share has ended.
    let isLive: Bool
    var diameter: CGFloat = 38

    /// A pulse is decorative motion that never stops, which is exactly what
    /// this setting is for. The face and its ring stay either way.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulsing = false

    private var showsPulse: Bool { isLive && !reduceMotion }

    var body: some View {
        ZStack {
            if showsPulse {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.35))
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(pulsing ? 2.1 : 1)
                    .opacity(pulsing ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.8).repeatForever(autoreverses: false),
                        value: pulsing
                    )
                    // Driven by the halo's own lifecycle rather than the
                    // parent's: it is created when the share starts and
                    // removed when it ends, so this covers both directions
                    // without watching `isLive` from outside.
                    .onAppear { pulsing = true }
                    .onDisappear { pulsing = false }
            }

            avatar
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(isLive ? Color.brandPrimary : Color.white, lineWidth: 2.5)
                }
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        }
        // The halo scales past the frame; without room for it the mini-map
        // clips it into a square.
        .frame(width: diameter * 2.2, height: diameter * 2.2)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL, !avatarURL.isEmpty {
            CircularProfileImageView(avatarURL, size: .custom(diameter))
        } else {
            Circle()
                .fill(Color(.systemGray3))
                .overlay {
                    Text(initial)
                        .font(.system(size: diameter * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
    }

    private var initial: String {
        let trimmed = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}
