//
//  ChatTimeFormat+DisplayName.swift
//  FeatureChat
//
//  The translated label for the clock-style setting.
//

import Foundation
import WaanguCoreKit

extension ChatTimeFormat {

    var translationKey: String {
        switch self {
        case .hour24: return ChatTranslationKeys.SETTINGS_TIME_FORMAT_24H
        case .hour12: return ChatTranslationKeys.SETTINGS_TIME_FORMAT_12H
        }
    }

    /// Resolved through the chat module, falling back to the English label.
    ///
    /// The enum lives in CoreKit, which owns no translation keys — so the label
    /// has to be resolved here, where they are. Same shape as
    /// `ChatAppearance.displayName(translationService:)`.
    func displayName(translationService: (any TranslationServiceProtocol)?) -> String {
        translationService?
            .resolve(key: translationKey, module: ChatTranslationKeys.MODULE)
            .value ?? fallbackDisplayName
    }
}
