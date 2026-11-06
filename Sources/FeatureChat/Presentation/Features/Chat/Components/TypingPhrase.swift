import Foundation
import WaanguCoreKit

/// The sentence shown while someone is typing, shared by the chat room
/// indicator and the discussion list row so the two never word it differently.
///
/// Direct chats drop the name: the row title and the room's navigation bar
/// already say who this is, and "Alice is typing…" under Alice's own name reads
/// like a second person. Groups keep it — that is the whole information there.
enum TypingPhrase {

    static func text(
        for users: [TypingUser],
        isGroup: Bool,
        translator: (any TranslationServiceProtocol)?
    ) -> String? {
        guard let first = users.first else { return nil }

        if isGroup && users.count > 1 {
            return resolve(
                key: ChatTranslationKeys.TYPING_MULTIPLE,
                args: ["\(users.count)"],
                fallback: "\(users.count) people are typing...",
                translator: translator
            )
        }

        let isRecording = first.messageType != .TEXT

        guard isGroup else {
            return resolve(
                key: isRecording
                    ? ChatTranslationKeys.RECORDING_AUDIO_DIRECT
                    : ChatTranslationKeys.TYPING_TEXT_DIRECT,
                args: [],
                fallback: isRecording ? "recording a voice message..." : "typing...",
                translator: translator
            )
        }

        // A group typist we could not name falls back to whatever the wire
        // carried — a phone number rather than a blank sentence.
        let name = first.name.isEmpty ? first.senderId : first.name
        return resolve(
            key: isRecording
                ? ChatTranslationKeys.RECORDING_AUDIO
                : ChatTranslationKeys.TYPING_TEXT,
            args: [name],
            fallback: isRecording
                ? "\(name) is recording a voice message..."
                : "\(name) is typing...",
            translator: translator
        )
    }

    private static func resolve(
        key: String,
        args: [String],
        fallback: String,
        translator: (any TranslationServiceProtocol)?
    ) -> String {
        guard let translator else { return fallback }
        return translator.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value
    }
}
