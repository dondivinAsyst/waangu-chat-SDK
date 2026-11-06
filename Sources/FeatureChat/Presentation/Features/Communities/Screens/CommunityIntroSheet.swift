//
//  CommunityIntroSheet.swift
//  FeatureChat
//

import SwiftUI
import WaanguCoreKit

/// The first step of creating a community: what one is, before the form.
@available(iOS 16.0, *)
struct CommunityIntroSheet: View {

    let translationService: (any TranslationServiceProtocol)?
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        IntroSheetView(
            symbol: "person.3.fill",
            title: t(ChatTranslationKeys.COMMUNITIES_INTRO_TITLE),
            body: t(ChatTranslationKeys.COMMUNITIES_INTRO_BODY),
            points: [
                IntroSheetPoint(
                    symbol: "rectangle.3.group",
                    title: t(ChatTranslationKeys.COMMUNITIES_INTRO_GROUPS),
                    detail: t(ChatTranslationKeys.COMMUNITIES_INTRO_GROUPS_DESC)
                ),
                IntroSheetPoint(
                    symbol: "megaphone",
                    title: t(ChatTranslationKeys.COMMUNITIES_INTRO_ANNOUNCE),
                    detail: t(ChatTranslationKeys.COMMUNITIES_INTRO_ANNOUNCE_DESC)
                ),
                IntroSheetPoint(
                    symbol: "person.badge.plus",
                    title: t(ChatTranslationKeys.COMMUNITIES_INTRO_MEMBERS),
                    detail: t(ChatTranslationKeys.COMMUNITIES_INTRO_MEMBERS_DESC)
                )
            ],
            confirmTitle: t(ChatTranslationKeys.COMMUNITIES_GET_STARTED),
            onConfirm: onStart,
            onDismiss: onDismiss
        )
    }

    private func t(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE).value ?? key
    }
}
