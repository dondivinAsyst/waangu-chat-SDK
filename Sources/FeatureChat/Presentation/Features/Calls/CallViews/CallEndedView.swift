//
//  CallEndedView.swift
//  FeatureChat
//
//  How a call finished, and what to do about it.
//
//  A call that connected and was hung up just closes itself. One that never
//  connected — no answer, declined, busy, failed — holds this screen, because
//  "call again" is usually what the user wants next and making them navigate
//  back to find the contact is the wrong answer.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct CallEndedView: View {
    let callerName: String
    let callerImage: String?
    let translationService: (any TranslationServiceProtocol)?
    /// Records a voice message for the person who did not pick up. Absent while
    /// no recorder is wired in, which also hides the button.
    var onRecordVoiceMessage: (() -> Void)?

    init(
        callerName: String,
        callerImage: String?,
        translationService: (any TranslationServiceProtocol)? = nil,
        onRecordVoiceMessage: (() -> Void)? = nil
    ) {
        self.callerName = callerName
        self.callerImage = callerImage
        self.translationService = translationService
        self.onRecordVoiceMessage = onRecordVoiceMessage
    }

    @ObservedObject private var voip = VoipManager.shared

    /// A call that the server could not carry, that rang out, or that was turned
    /// down did not simply "end" — saying so leaves the user guessing.
    private var reasonKey: String {
        switch voip.endReason {
        case .hungUp:   return ChatTranslationKeys.CALLS_ENDED
        case .failed:   return ChatTranslationKeys.CALLS_FAILED
        case .noAnswer: return ChatTranslationKeys.CALLS_NO_ANSWER
        case .declined: return ChatTranslationKeys.CALLS_DECLINED
        case .busy:     return ChatTranslationKeys.CALLS_BUSY
        }
    }

    /// Only a call that never connected is worth offering to place again.
    private var showsActions: Bool {
        voip.endReason != .hungUp
    }

    var body: some View {
        ZStack {
            CallDoodleBackground()

            VStack(spacing: 0) {
                Spacer()

                CircularProfileImageView(callerImage, size: .custom(120))
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))

                Text(callerName)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 32)
                    .padding(.top, 22)

                Text(t(reasonKey))
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.top, 6)

                Spacer()

                if showsActions {
                    actions
                        .padding(.bottom, safeAreaInsets.bottom + 30)
                }
            }
        }
        .statusBar(hidden: false)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(alignment: .top, spacing: 34) {
            action(
                icon: "xmark",
                label: t(ChatTranslationKeys.CALLS_CANCEL),
                background: .white,
                foreground: .black,
                action: { voip.dismissEndedCall() }
            )

            if let onRecordVoiceMessage {
                action(
                    icon: "mic.fill",
                    label: t(ChatTranslationKeys.CALLS_RECORD_VOICE_MESSAGE),
                    background: .white.opacity(0.14),
                    foreground: .white,
                    action: onRecordVoiceMessage
                )
            }

            action(
                icon: "phone.fill",
                label: t(ChatTranslationKeys.CALLS_CALL_AGAIN),
                background: CallTheme.Palette.acceptAudio,
                foreground: .white,
                action: { voip.redialLastCall() }
            )
        }
        .padding(.horizontal, 24)
    }

    private func action(
        icon: String,
        label: String,
        background: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Button(action: action) {
                Circle()
                    .fill(background)
                    .frame(width: 66, height: 66)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(foreground)
                    )
            }
            .buttonStyle(.plain)

            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 96)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
