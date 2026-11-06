import Foundation

/// Gives a bare group lifecycle payload the message envelope it lacks.
///
/// Two wire shapes carry these events:
///
/// - **Wrapped** — the live one. An ordinary `MESSAGE_SENT` envelope with the
///   event nested in `content`. It needs nothing from this type: it already has a
///   `codeMessage`, a `conversationId` and a content object, and `MessageContentDTO`
///   reads the event straight out of it on every inbound path.
/// - **Flat** — the whole event at the top level with no envelope at all. It has
///   no `codeMessage` and no `content`, so `InboundMessageDTO` cannot decode it.
///   This type builds the envelope around it.
///
/// The event's own fields are moved under `content` rather than rewritten, so both
/// shapes end up identical by the time anything interprets them — there is one
/// place that decides what a group event means, and it is `ResolvedGroupEvent`.
enum GroupSystemEventNormalizer {

    /// Returns `nil` when the payload cannot be placed in a conversation, which is
    /// the one field no fallback can invent.
    static func normalize(_ json: [String: Any], eventType: String) -> [String: Any]? {
        guard let conversationId = string(json["conversationId"]), !conversationId.isEmpty else {
            return nil
        }

        var content = json
        content["eventType"] = eventType

        let timestamp = timestamp(in: json)

        var envelope: [String: Any] = [:]
        envelope["conversationId"] = conversationId
        envelope["groupId"] = string(json["groupId"]) ?? conversationId
        envelope["typeMessage"] = eventType
        envelope["content"] = content
        envelope["isMessageSystem"] = true
        // Filled in properly by the mapper from the content actor; present only
        // because `InboundMessageDTO` refuses to decode without them.
        envelope["senderId"] = ""
        envelope["senderName"] = ""
        envelope["codeMessage"] = messageId(in: json)
            ?? synthesizedId(
                eventType: eventType,
                conversationId: conversationId,
                targetUserId: string(json["targetUserId"]),
                timestamp: timestamp,
                payload: json
            )
        if let timestamp {
            envelope["timestamp"] = timestamp
        }
        return envelope
    }

    // MARK: - Identity

    private static func messageId(in json: [String: Any]) -> String? {
        nonEmpty(
            string(json["codeMessage"])
                ?? string(json["messageId"])
                ?? string(json["eventId"])
                ?? string(json["id"])
        )
    }

    /// Derives an id when the payload carries none, so a replayed event updates the
    /// row it already wrote instead of inserting a second bubble.
    ///
    /// Identity is the event kind, the conversation, the target and the time it
    /// happened; with no timestamp the whole payload is hashed instead, which still
    /// collapses an exact replay but would confuse two genuinely distinct events
    /// with identical content.
    private static func synthesizedId(
        eventType: String,
        conversationId: String,
        targetUserId: String?,
        timestamp: Double?,
        payload: [String: Any]
    ) -> String {
        if let timestamp {
            let identity = [
                eventType,
                conversationId,
                targetUserId ?? "",
                String(Int64(timestamp.rounded()))
            ].joined(separator: "|")
            return ChatDeterministicId.uuid(from: identity)
        }

        let stable = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) }
        return ChatDeterministicId.uuid(from: stable ?? "\(eventType)|\(conversationId)")
    }

    /// In seconds. `InboundMessageDTO.resolvedTimestamp` takes `timestamp` as-is,
    /// so handing it the epoch millis the wire sends would date the message some
    /// fifty thousand years out.
    private static func timestamp(in json: [String: Any]) -> Double? {
        for key in ["createdAt", "timestamp", "updatedAt", "at"] {
            if let number = json[key] as? NSNumber {
                let raw = number.doubleValue
                return raw > 10_000_000_000 ? raw / 1000 : raw
            }
        }
        return nil
    }

    // MARK: - Primitives

    private static func string(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : $0 }
    }
}
