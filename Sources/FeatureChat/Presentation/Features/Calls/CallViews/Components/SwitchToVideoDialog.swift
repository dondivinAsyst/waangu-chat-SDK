//
//  SwitchToVideoDialog.swift
//  FeatureChat
//
//  One confirmation used for both ways an audio call becomes a video call:
//  the user asking for video directly, and the user asking to share their
//  screen (which needs the video stage to render into).
//
//  The screen-share variant cannot be a plain button. `RPSystemBroadcastPickerView`
//  has no programmatic trigger, so the confirm control *hosts* the picker and the
//  camera upgrade rides along on the same tap. iOS then adds its own confirmation
//  and a three-second countdown, which is ample time for the camera to come up
//  before the first frame arrives and pauses it again.
//

import SwiftUI
import WaanguCoreKit

/// Why the call is being asked to switch to video.
///
/// Top-level rather than nested in the view because `VoipManager` publishes it:
/// the request can come from the call panel or from the more sheet, and both
/// have to raise the same dialog over the call.
enum CallVideoSwitchIntent {
        /// Confirm hosts the system broadcast picker.
        case shareScreen
        /// Confirm is an ordinary button.
        case videoCall

        var titleKey: String {
            switch self {
            case .shareScreen: return ChatTranslationKeys.CALLS_SHARE_SCREEN_TITLE
            case .videoCall:   return ChatTranslationKeys.CALLS_SWITCH_VIDEO_TITLE
            }
        }

        var messageKey: String {
            switch self {
            case .shareScreen: return ChatTranslationKeys.CALLS_SHARE_SCREEN_MESSAGE
            case .videoCall:   return ChatTranslationKeys.CALLS_SWITCH_VIDEO_MESSAGE
            }
        }

        var confirmKey: String {
            switch self {
            case .shareScreen: return ChatTranslationKeys.CALLS_SHARE_SCREEN_ACTION
            case .videoCall:   return ChatTranslationKeys.CALLS_SWITCH_VIDEO_ACTION
            }
        }

        var icon: String {
            switch self {
            case .shareScreen: return "rectangle.inset.filled.and.person.filled"
            case .videoCall:   return "video.fill"
            }
        }
}

struct SwitchToVideoDialog: View {

    let intent: CallVideoSwitchIntent
    let translationService: (any TranslationServiceProtocol)?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private func t(_ key: String) -> String {
        translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: []
        ).value ?? key
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 18) {
                Image(systemName: intent.icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(CallTheme.Palette.primaryText)
                    .padding(.top, 4)

                Text(t(intent.titleKey))
                    .font(.headline)
                    .foregroundStyle(CallTheme.Palette.primaryText)
                    .multilineTextAlignment(.center)

                Text(t(intent.messageKey))
                    .font(.subheadline)
                    .foregroundStyle(CallTheme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    confirmControl
                    Button(action: onCancel) {
                        Text(t(ChatTranslationKeys.CALLS_CANCEL))
                            .font(.body.weight(.medium))
                            .foregroundStyle(CallTheme.Palette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(CallTheme.Palette.canvasElevated)
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var confirmControl: some View {
        let label = Text(t(intent.confirmKey))
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CallTheme.Palette.acceptVideo)
            )

        switch intent {
        case .videoCall:
            Button(action: onConfirm) { label }

        case .shareScreen:
            // The picker is a UIKit button with its own action, so it is laid
            // over the styled label and takes the tap. `simultaneousGesture`
            // runs the camera upgrade on that same tap — SwiftUI delivers it
            // alongside the UIKit action rather than instead of it.
            label
                .overlay {
                    BroadcastPickerButton()
                        .opacity(0.02)
                        .allowsHitTesting(true)
                }
                .simultaneousGesture(TapGesture().onEnded { onConfirm() })
        }
    }
}
