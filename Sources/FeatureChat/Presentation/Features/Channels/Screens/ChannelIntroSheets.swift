//
//  ChannelIntroSheets.swift
//  FeatureChat
//
//  The two channel intros: consent once, and the explainer before creating.
//

import SwiftUI
import WaanguCoreKit

/// Shown once, before channels are used at all.
///
/// The acceptance is remembered per device — it explains a feature, it is not a
/// server-side consent, so it belongs in local storage and nowhere else.
@available(iOS 16.0, *)
struct ChannelsWelcomeSheet: View {

    let translationService: (any TranslationServiceProtocol)?
    let onAgree: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        IntroSheetView(
            symbol: "dot.radiowaves.left.and.right",
            title: t(ChatTranslationKeys.CHANNELS_INTRO_TITLE),
            points: [
                IntroSheetPoint(
                    symbol: "newspaper",
                    title: t(ChatTranslationKeys.CHANNELS_INTRO_UPDATES),
                    detail: t(ChatTranslationKeys.CHANNELS_INTRO_UPDATES_DESC)
                ),
                IntroSheetPoint(
                    symbol: "globe",
                    title: t(ChatTranslationKeys.CHANNELS_INTRO_DISCOVER),
                    detail: t(ChatTranslationKeys.CHANNELS_INTRO_DISCOVER_DESC)
                ),
                IntroSheetPoint(
                    symbol: "phone.badge.checkmark",
                    title: t(ChatTranslationKeys.CHANNELS_INTRO_PRIVACY),
                    detail: t(ChatTranslationKeys.CHANNELS_INTRO_PRIVACY_DESC)
                )
            ],
            confirmTitle: t(ChatTranslationKeys.CHANNELS_INTRO_AGREE),
            onConfirm: onAgree,
            onDismiss: onDismiss
        )
    }

    private func t(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE).value ?? key
    }
}

/// Shown every time, as the first step of creating a channel.
@available(iOS 16.0, *)
struct ChannelCreateIntroSheet: View {

    let translationService: (any TranslationServiceProtocol)?
    let onContinue: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        IntroSheetView(
            symbol: "dot.radiowaves.left.and.right",
            title: t(ChatTranslationKeys.CHANNELS_CREATE_INTRO_TITLE),
            points: [
                IntroSheetPoint(
                    symbol: "globe",
                    title: t(ChatTranslationKeys.CHANNELS_CREATE_INTRO_PUBLIC),
                    detail: t(ChatTranslationKeys.CHANNELS_CREATE_INTRO_PUBLIC_DESC)
                ),
                IntroSheetPoint(
                    symbol: "eye.slash",
                    title: t(ChatTranslationKeys.CHANNELS_CREATE_INTRO_HIDDEN),
                    detail: t(ChatTranslationKeys.CHANNELS_CREATE_INTRO_HIDDEN_DESC)
                ),
                IntroSheetPoint(
                    symbol: "checkmark.shield",
                    title: t(ChatTranslationKeys.CHANNELS_CREATE_INTRO_RESPONSIBLE),
                    detail: t(ChatTranslationKeys.CHANNELS_CREATE_INTRO_RESPONSIBLE_DESC)
                )
            ],
            confirmTitle: t(ChatTranslationKeys.CHANNELS_CONTINUE),
            onConfirm: onContinue,
            onDismiss: onDismiss
        )
    }

    private func t(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE).value ?? key
    }
}
