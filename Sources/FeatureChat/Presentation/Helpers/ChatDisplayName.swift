//
//  ChatDisplayName.swift
//  FeatureChat
//
//  What to put where a person's name goes.
//

import Foundation
import WaanguSharedUI
import WaanguCoreKit

/// The one ladder every surface climbs: a name, else the number, else a phrase
/// that admits we don't know.
///
/// Each surface used to improvise its own ending — the chat list rendered
/// `userName ?? ""`, the room header the same, so a peer we had no name for
/// appeared as a blank line in one place and a raw id in another. Both are
/// worse than the number, which is what the conversation is addressed to and
/// what the user recognises when the contact isn't saved.
enum ChatDisplayName {

    static func text(
        name: String?,
        phone: String?,
        identifiers: [String] = [],
        translator: (any TranslationServiceProtocol)?
    ) -> String {
        let resolved = PeerDisplayName.sanitized(name, identifiers: identifiers)
        if !resolved.isEmpty { return resolved }

        let number = phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !number.isEmpty, !PeerDisplayName.looksLikeIdentifier(number) {
            return PhoneNumberFormatter.format(number)
        }

        return unknownUser(translator)
    }

    /// The translated phrase, or plain English — but never the raw key.
    ///
    /// `resolve` returns the key itself when it cannot find it, so a payload
    /// shipped without `chat_unknown_user` would print `chat_unknown_user` in
    /// the inbox. This is a new key, and payloads are served remotely: a device
    /// on an older payload has to read something a person would recognise.
    private static func unknownUser(_ translator: (any TranslationServiceProtocol)?) -> String {
        let fallback = "Unknown user"
        guard let translator else { return fallback }

        let result = translator.resolve(
            key: ChatTranslationKeys.CHAT_UNKNOWN_USER,
            module: ChatTranslationKeys.MODULE
        )
        let missing = result.resolution == .keyFallback
            || result.value == ChatTranslationKeys.CHAT_UNKNOWN_USER
            || result.value.isEmpty
        guard !missing else { return fallback }
        return result.value
    }
}
