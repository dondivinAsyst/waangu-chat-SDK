//
//  ViewOnceMessageViewer.swift
//  FeatureChat
//

import WaanguCoreKit
import WaanguSharedUI
import SwiftUI

/// The one place a view-once message is ever shown: its real bubble, full
/// screen, as on WhatsApp. Closing it is final — the thread only ever shows
/// "Opened" afterwards.
struct ViewOnceMessageViewer<Content: View>: View {
    let translationService: (any TranslationServiceProtocol)?
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            // The real bubble. Its forward button is already hidden for view-once
            // messages, and there is no message menu here to reply or copy from.
            content()

            Spacer(minLength: 0)

            Text(t(ChatTranslationKeys.CHAT_VIEW_ONCE_CLOSE_HINT, fallback: "Once you close it, it can't be opened again."))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(AppColors.primary)
                Text(t(ChatTranslationKeys.CHAT_A11Y_VIEW_ONCE, fallback: "View once"))
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(t(ChatTranslationKeys.GALLERY_CLOSE, fallback: "Close"))
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func t(_ key: String, fallback: String) -> String {
        translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE)
            .value ?? fallback
    }
}
