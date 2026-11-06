//
//  CallParticipantTile.swift
//  FeatureChat
//
//  One person in a call.
//
//  Shows their camera when they are publishing one and avatar + waveform when
//  they are not — matching the 1:1 camera-off stage so a muted camera does not
//  look like a broken tile. Invited peers who have not joined yet get a
//  waiting card (no waveform) so the grid does not look like they are live.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct CallParticipantTile: View {

    let name: String
    let avatarURL: String?
    let track: (any CallVideoTrackProtocol)?
    var isMuted: Bool = false
    var isSharingScreen: Bool = false
    /// Mirrors the local preview, which is the only feed a user sees of
    /// themselves.
    var isMirrored: Bool = false
    /// Invited but not yet in the room — avatar + "Calling..." instead of live UI.
    var isWaiting: Bool = false
    var waitingLabel: String? = nil
    /// Their device is known to be ringing, rather than the invite only having
    /// been sent. Drives the pulse, so the two waiting states are not just two
    /// spellings of the same still card.
    var isRinging: Bool = false
    /// In the room, but their media stopped arriving — avatar + spinner instead
    /// of the frozen last frame.
    var isReconnecting: Bool = false
    var reconnectingLabel: String? = nil
    var showsName: Bool = true
    /// How loudly this person is speaking, `0…1`.
    var audioLevel: Float = 0
    /// This person's own colour, stable for the whole call.
    var color: Color = .white
    /// They are in the speaking queue — shows a hand badge until it clears.
    var hasRaisedHand: Bool = false
    /// An emoji floating briefly over the tile. Ephemeral by contract (§16.2):
    /// it is never written anywhere, it just plays and goes.
    var reaction: String? = nil

    private var showsVideo: Bool { track != nil }

    /// Drives the expanding halo on a ringing tile.
    @State private var ringPulse = false

    /// Room noise reads as a small non-zero level on any open microphone, so a
    /// plain `> 0` would leave every tile lit permanently and tell you nothing.
    private var isSpeaking: Bool {
        !isMuted && !isWaiting && !isReconnecting && audioLevel > 0.02
    }

    /// The border always carries the person's colour so a tile can be picked out
    /// at a glance; speaking only changes its strength. Identity and activity
    /// stay separate channels — one colour per person, brightness for who has
    /// the floor.
    private var borderColor: Color {
        if isWaiting { return Color.white.opacity(0.22) }
        if isReconnecting { return Color.white.opacity(0.28) }
        return color.opacity(isSpeaking ? 0.95 : 0.34)
    }

    private var borderWidth: CGFloat {
        guard isSpeaking else { return 1.5 }
        // Grows with loudness, capped so a shout does not swamp the tile.
        return 2 + CGFloat(min(max(audioLevel, 0), 1)) * 2
    }

    /// Derived from the name so each tile's bars sit at a different point in the
    /// cycle. Without it every waveform on screen moves as one.
    private var phaseSeed: Double {
        Double(abs(name.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % 997 })) / 997 * 6.28
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(CallTheme.Palette.canvasElevated)

            if isWaiting {
                waitingContent
            } else if isReconnecting {
                reconnectingContent
            } else if let track {
                CallVideoTrackView(track: track, isMirrored: isMirrored, fillsBounds: true)
                    .id(track.trackId)
            } else {
                cameraOffContent
            }

            badges
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(
                    borderColor,
                    style: StrokeStyle(
                        lineWidth: borderWidth,
                        dash: isWaiting ? [5, 4] : []
                    )
                )
                .animation(.easeOut(duration: 0.15), value: isSpeaking)
                .animation(.easeOut(duration: 0.15), value: borderWidth)
        )
        .overlay(alignment: .topLeading) {
            if hasRaisedHand {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(.black.opacity(0.45)))
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .center) {
            if let reaction {
                Text(reaction)
                    .font(.system(size: 44))
                    // Keyed on the emoji so a second reaction replays the
                    // animation instead of swapping the glyph in silently.
                    .id(reaction)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hasRaisedHand)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: reaction)
        .opacity(isWaiting || isReconnecting ? 0.92 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private static let cornerRadius: CGFloat = 18

    // MARK: - Waiting (invited, not joined)

    /// Avatar + moving dots, and a halo that pulses once their phone is actually
    /// ringing.
    ///
    /// Everything here moves on purpose. A still avatar over a still "Calling…"
    /// is indistinguishable from a tile that has stopped updating, which is
    /// exactly how it read: no way to tell a ringing invitee from a stuck one.
    private var waitingContent: some View {
        GeometryReader { proxy in
            let diameter = max(min(proxy.size.width, proxy.size.height) * 0.42, 36)
            VStack(spacing: 10) {
                CircularProfileImageView(avatarURL, size: .custom(diameter))
                    .overlay {
                        if isRinging {
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 2)
                                .scaleEffect(ringPulse ? 1.35 : 1)
                                .opacity(ringPulse ? 0 : 1)
                                .animation(
                                    .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                                    value: ringPulse
                                )
                        }
                    }

                VStack(spacing: 6) {
                    if let waitingLabel, !waitingLabel.isEmpty {
                        Text(waitingLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }

                    CallConnectingDots(
                        dotSize: 4,
                        spacing: 4,
                        tint: .white.opacity(0.6)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // A repeating animation only runs once its driving value changes, so the
        // halo has to be kicked off after the tile is on screen.
        .onAppear { ringPulse = true }
    }

    // MARK: - Reconnecting (in the room, media stopped arriving)

    /// Avatar + spinner. Deliberately not the waiting card: this person *is* on
    /// the call, and a dashed "Calling…" tile would read as though they had
    /// never joined.
    private var reconnectingContent: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) * 0.42
            VStack(spacing: 10) {
                CircularProfileImageView(avatarURL, size: .custom(max(diameter, 36)))
                    .opacity(0.55)

                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white.opacity(0.75))
                        .scaleEffect(0.7)

                    if let reconnectingLabel, !reconnectingLabel.isEmpty {
                        Text(reconnectingLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Camera off

    /// Avatar + live waveform (when unmuted), same language as 1:1 mute stages.
    private var cameraOffContent: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) * 0.42
            VStack(spacing: 10) {
                CircularProfileImageView(avatarURL, size: .custom(max(diameter, 36)))

                if !isMuted {
                    CallAudioWaveformView(
                        level: audioLevel,
                        phaseSeed: phaseSeed,
                        tint: color
                    )
                    .scaleEffect(min(proxy.size.width, proxy.size.height) < 140 ? 0.55 : 0.75)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Badges

    private var badges: some View {
        VStack {
            if isSharingScreen {
                HStack {
                    Label {
                        Text(verbatim: name)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "rectangle.inset.filled.and.person.filled")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(CallTheme.Palette.acceptVideo))
                    Spacer(minLength: 0)
                }
                .padding(8)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if isMuted && !isWaiting && !isReconnecting {
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }

                if showsName {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                }

                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }

    private var accessibilityDescription: String {
        var parts = [name]
        if isWaiting { parts.append(waitingLabel ?? "waiting") }
        if isReconnecting { parts.append(reconnectingLabel ?? "reconnecting") }
        if isMuted { parts.append("muted") }
        if isSharingScreen { parts.append("sharing screen") }
        if !showsVideo && !isWaiting && !isReconnecting { parts.append("camera off") }
        return parts.joined(separator: ", ")
    }
}

/// Stands in for everyone who did not fit on screen.
struct CallOverflowTile: View {

    let count: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CallTheme.Palette.canvasElevated)

            Text(verbatim: "+\(count)")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(CallTheme.Palette.primaryText)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel("\(count) more participants")
    }
}
