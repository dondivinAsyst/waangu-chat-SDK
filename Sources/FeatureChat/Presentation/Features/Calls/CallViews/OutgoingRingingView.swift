//
//  OutgoingRingingView.swift
//  FeatureChat
//
//  Outgoing call, before anyone picks up.
//
//  Deliberately the same furniture as the connected screen — same top bar, same
//  control panel — because from the user's side nothing has changed except that
//  the far end has not answered yet. Only the subtitle differs: "Calling…" while
//  the offer is in flight, "Ringing…" once the callee is actually being alerted.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct OutgoingRingingView: View {
    let callerName: String
    let callerImage: String?
    let isVideo: Bool
    let translationService: (any TranslationServiceProtocol)?

    var onAddParticipant: () -> Void = {}
    var onOpenChat: () -> Void = {}
    var onMore: () -> Void = {}
    var onShare: () -> Void = {}

    init(
        callerName: String,
        callerImage: String?,
        isVideo: Bool,
        translationService: (any TranslationServiceProtocol)? = nil,
        onAddParticipant: @escaping () -> Void = {},
        onOpenChat: @escaping () -> Void = {},
        onMore: @escaping () -> Void = {},
        onShare: @escaping () -> Void = {}
    ) {
        self.callerName = callerName
        self.callerImage = callerImage
        self.isVideo = isVideo
        self.translationService = translationService
        self.onAddParticipant = onAddParticipant
        self.onOpenChat = onOpenChat
        self.onMore = onMore
        self.onShare = onShare
    }

    @ObservedObject private var voip = VoipManager.shared

    /// True once the callee's device is actually being alerted.
    private var isFarEndRinging: Bool {
        voip.callStatus == .ringing
    }

    /// Whatever the call manager says is happening — "Connecting…", "Calling…",
    /// "Ringing…", and equally "Busy" or "No answer" in the moment before the
    /// screen closes, so the user always sees the outcome rather than a status
    /// frozen on "Calling…".
    private var statusKey: String {
        voip.callStatus.translationKey
    }

    var body: some View {
        ZStack {
            CallDoodleBackground()

            VStack(spacing: 0) {
                Spacer().frame(height: safeAreaInsets.top + 8)

                CallTopBar(
                    title: groupAwareTitle,
                    subtitle: t(statusKey),
                    onMinimize: { voip.minimize() },
                    onAddParticipant: onAddParticipant,
                    onOpenChat: onOpenChat
                )

                Spacer()

                avatar

                Spacer()

                controlPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, safeAreaInsets.bottom + 16)
            }
        }
        .statusBar(hidden: false)
    }

    /// The other person's name one-to-one; how many people, in a group.
    private var groupAwareTitle: String {
        guard voip.isGroupCall else {
            return voip.oneToOneTitle(unknownLabel: t(ChatTranslationKeys.CALLS_UNKNOWN))
        }
        let count = t(
            ChatTranslationKeys.CALLS_PARTICIPANT_COUNT,
            args: ["\(voip.participantCount)"]
        )
        return "\(t(ChatTranslationKeys.CALLS_GROUP_CALL)) · \(count)"
    }

    // MARK: - Avatar

    private var avatar: some View {
        CircularProfileImageView(callerImage, size: .custom(210))
            .overlay(
                Circle().stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .overlay(
                // The pulse mirrors the far end ringing; showing it while the
                // offer is still in flight suggests something is happening there
                // when nothing is yet.
                Group {
                    if isFarEndRinging {
                        RingingPulseView()
                    }
                }
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
            .accessibilityHidden(true)
    }

    // MARK: - Controls

    /// Hang up, speaker, and mute work while ringing; the rest waits for connect.
    ///
    /// There is no camera / room membership yet, so video / invite / more stay
    /// disabled. Mute is a preference recorded now and applied the moment the
    /// mic track is produced after the peer answers.
    private var controlPanel: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 22) {
            GridRow {
                CallControlButton(
                    icon: "video.fill",
                    label: t(ChatTranslationKeys.CALLS_VIDEO),
                    isActive: voip.hasVideo,
                    isEnabled: false,
                    action: { voip.toggleVideo() }
                )
                .frame(maxWidth: .infinity)

                CallControlButton(
                    icon: voip.isOnSpeaker ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    label: t(ChatTranslationKeys.CALLS_SPEAKER),
                    isActive: voip.isOnSpeaker,
                    action: { voip.toggleSpeaker() }
                )
                .frame(maxWidth: .infinity)

                CallControlButton(
                    icon: voip.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: t(ChatTranslationKeys.CALLS_MUTE),
                    isActive: voip.isMuted,
                    action: { voip.toggleMute() }
                )
                .frame(maxWidth: .infinity)
            }

            GridRow {
                CallControlButton(
                    icon: "ellipsis",
                    label: t(ChatTranslationKeys.CALLS_MORE),
                    isEnabled: false,
                    action: onMore
                )
                .frame(maxWidth: .infinity)

                CallControlButton(
                    icon: "rectangle.inset.filled.and.person.filled",
                    label: t(ChatTranslationKeys.CALLS_SHARE),
                    isEnabled: false,
                    action: onShare
                )
                .frame(maxWidth: .infinity)

                CallControlButton(
                    icon: "phone.down.fill",
                    label: t(ChatTranslationKeys.CALLS_END),
                    role: .destructive,
                    action: { voip.endCall() }
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CallTheme.Metric.panelCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

struct RingingPulseView: View {
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(Color.white.opacity(animate ? 0 : 0.15), lineWidth: 2)
            .frame(width: animate ? 260 : 215, height: animate ? 260 : 215)
            .animation(
                .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                value: animate
            )
            .onAppear { animate = true }
    }
}
