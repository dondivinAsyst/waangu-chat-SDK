//
//  IncomingCallView.swift
//  FeatureChat
//
//  Full-screen incoming call when the user expands from the minimized banner
//  while unlocked. Decline / Accept buttons are the in-app affordance.
//
//  Slide-to-answer is owned by CallKit on the lock screen — not this view.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct IncomingCallView: View {

    let callerName: String
    let callerImage: String?
    let isVideo: Bool
    let translationService: (any TranslationServiceProtocol)?

    /// The reference design leaves the centre empty; flip this on to show the
    /// caller's avatar instead.
    var showsAvatar: Bool = false
    var onMessage: () -> Void = {}
    var onRemindMe: () -> Void = {}

    init(
        callerName: String,
        callerImage: String?,
        isVideo: Bool,
        translationService: (any TranslationServiceProtocol)? = nil,
        showsAvatar: Bool = false,
        onMessage: @escaping () -> Void = {},
        onRemindMe: @escaping () -> Void = {}
    ) {
        self.callerName = callerName
        self.callerImage = callerImage
        self.isVideo = isVideo
        self.translationService = translationService
        self.showsAvatar = showsAvatar
        self.onMessage = onMessage
        self.onRemindMe = onRemindMe
    }

    @ObservedObject private var voip = VoipManager.shared

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer().frame(height: safeAreaInsets.top + 44)

                header
                callerTitle

                Spacer(minLength: 24)

                if showsAvatar {
                    avatar
                    Spacer(minLength: 24)
                }

                secondaryActions
                    .padding(.bottom, 44)

                primaryAction
                    .padding(.bottom, safeAreaInsets.bottom + 26)
            }
        }
        .statusBar(hidden: false)
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [CallTheme.Palette.incomingTop, CallTheme.Palette.incomingBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    /// App badge + call kind, mirroring how the system labels a third-party call.
    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(CallTheme.Palette.acceptAudio)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: isVideo ? "video.fill" : "phone.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                )

            Text(callKindLabel)
                .font(CallTheme.TextStyle.incomingSubtitle)
                .foregroundStyle(CallTheme.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// "Video call", or "Group video call · 4 participants" — a group call has
    /// to say so before it is answered, not after.
    private var callKindLabel: String {
        let kind = isVideo
            ? t(ChatTranslationKeys.CALLS_VIDEO_CALL)
            : t(ChatTranslationKeys.CALLS_AUDIO_CALL)

        guard voip.isGroupCall else { return kind }

        // Counted off the deduped roster (and including this device), the same
        // list `isGroupCall` reads — the raw count could disagree with it.
        let count = t(
            ChatTranslationKeys.CALLS_PARTICIPANT_COUNT,
            args: ["\(voip.participantCount)"]
        )
        return "\(kind) · \(count)"
    }

    private var callerTitle: some View {
        VStack(spacing: 10) {
            Text(callerName)
                .font(CallTheme.TextStyle.incomingTitle)
                .foregroundStyle(CallTheme.Palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 24)
                .padding(.top, 6)

            // B61 — le chiffrement de bout en bout des appels n'est pas démontré.
            if ChatEncryptionClaim.messagesAreEndToEndEncrypted {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text(t(ChatTranslationKeys.CALLS_E2EE))
                        .font(.system(size: 12))
                }
                .foregroundStyle(CallTheme.Palette.tertiaryText)
            }
        }
    }

    private var avatar: some View {
        CircularProfileImageView(callerImage, size: .custom(130))
            .overlay(
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
            )
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        HStack(spacing: 0) {
            secondaryAction(
                icon: "message.fill",
                label: t(ChatTranslationKeys.CALLS_MESSAGE),
                action: onMessage
            )
            .frame(maxWidth: .infinity)

            secondaryAction(
                icon: "alarm.fill",
                label: t(ChatTranslationKeys.CALLS_REMIND_ME),
                action: onRemindMe
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
    }

    private func secondaryAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.13))
                        .frame(
                            width: CallTheme.Metric.secondaryActionDiameter,
                            height: CallTheme.Metric.secondaryActionDiameter
                        )
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                }
                Text(label)
                    .font(CallTheme.TextStyle.actionLabel)
                    .foregroundStyle(CallTheme.Palette.primaryText)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Primary action

    private var primaryAction: some View {
        HStack(spacing: 0) {
            answerButton(
                icon: "xmark",
                label: t(ChatTranslationKeys.CALLS_DECLINE),
                tint: CallTheme.Palette.declineCall,
                action: { voip.declineCall() }
            )
            .frame(maxWidth: .infinity)

            answerButton(
                icon: "checkmark",
                label: t(ChatTranslationKeys.CALLS_ACCEPT),
                tint: CallTheme.Palette.acceptVideo,
                action: { voip.answerCall() }
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
    }

    private func answerButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(
                            width: CallTheme.Metric.primaryActionDiameter,
                            height: CallTheme.Metric.primaryActionDiameter
                        )
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(label)
                    .font(CallTheme.TextStyle.actionLabel)
                    .foregroundStyle(CallTheme.Palette.primaryText)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Localisation

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
