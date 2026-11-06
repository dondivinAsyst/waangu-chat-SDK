//
//  ChatRoomPresenceText.swift
//  FeatureChat
//
//  The line under the name in a chat room header.
//

import Foundation
import WaanguCoreKit

/// Turns what we actually know about a peer's presence into the header subtitle.
///
/// The room used to build this string from `Date()` at the moment it opened, so
/// every conversation claimed the other person had been seen seconds ago — a
/// number invented on the spot and never corrected. An unknown last-seen is
/// better said with silence: this returns nil, and the header draws nothing.
///
/// This reads the presence cache once, at open. It does not update while the
/// room is on screen — `UserPresenceStore` publishes nothing to observe — so a
/// peer who comes online is only reflected the next time the room is opened.
enum ChatRoomPresenceText {

    static func status(
        for userId: String,
        translator: (any TranslationServiceProtocol)? = nil
    ) -> UserOnline {
        let presence = UserPresenceStore.shared.presence(for: userId)

        return UserOnline(
            status: UserStatus(rawValue: presence?.status.rawValue ?? "") ?? .offline,
            lastSeen: lastSeen(from: presence?.lastSeen, translator: translator) ?? "",
            userId: userId
        )
    }

    /// `nil` when the wire gave us nothing parseable — say nothing rather than
    /// guess.
    private static func lastSeen(from raw: String?, translator: (any TranslationServiceProtocol)?) -> String? {
        guard let raw, !raw.isEmpty, let date = parseDate(raw) else { return nil }
        return lastSeenText(at: date, translator: translator)
    }

    /// "last seen <day> at <time>" in the app's language (SDK plan, step 1.15).
    ///
    /// The day comes from the system's relative formatting ("today", "yesterday",
    /// then the date) and the time is always a time — the English version this
    /// replaces printed a date after "at" for any day before today. Both follow
    /// `locale`, as the timeline headers do (`ChatRoomTimelineBuilder`).
    static func lastSeenText(
        at date: Date,
        translator: (any TranslationServiceProtocol)?,
        locale: Locale = .current
    ) -> String {
        let day = DateFormatter()
        day.locale = locale
        day.dateStyle = .medium
        day.timeStyle = .none
        day.doesRelativeDateFormatting = true

        let time = DateFormatter()
        time.locale = locale
        time.dateStyle = .none
        time.timeStyle = .short

        let args = [day.string(from: date), time.string(from: date)]
        guard let translator else { return "last seen \(args[0]) at \(args[1])" }
        return translator.resolve(
            key: ChatTranslationKeys.CHAT_LAST_SEEN_AT,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
