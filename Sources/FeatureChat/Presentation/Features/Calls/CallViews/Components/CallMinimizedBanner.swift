//
//  CallMinimizedBanner.swift
//  FeatureChat
//
//  The strip that replaces the call screen once the call is minimised.
//
//  Sits above the tab view and pushes the app's content down rather than
//  floating over it, so nothing is ever hidden behind it — the same placement
//  the mini audio player already uses. Tapping anywhere restores the call.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct CallMinimizedBanner: View {

    let callerName: String
    let duration: String
    let isVideo: Bool
    let translationService: (any TranslationServiceProtocol)?

    var onTap: () -> Void
    var onEnd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isVideo ? "video.fill" : "phone.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 1) {
                Text(callerName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(t(ChatTranslationKeys.CALLS_TAP_TO_RETURN))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(duration)
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)

            // Hanging up without going back to the call screen first, the way
            // the system call banner behaves.
            Button(action: onEnd) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(CallTheme.Palette.endCall)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t(ChatTranslationKeys.CALLS_END)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(AppColors.primary)
        // The whole strip is the return-to-call target; the end button above
        // takes its own taps first.
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
