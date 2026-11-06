import Foundation

/// Turns raw user-inbox JSON into a call event.
///
/// Calls share `waangu-chat/{userId}` with messages and stories, so the first
/// job is rejecting anything that is not `category == "call"` — otherwise the
/// call state machine would react to chat traffic.
enum CallMqttEventParser {

    static func parse(data: Data) -> InboundCallEventDTO? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parse(json: json)
    }

    static func parse(json: [String: Any]) -> InboundCallEventDTO? {
        // Some events omit `category` but carry a CALL_* type; accept either,
        // and nothing else.
        let category = (json["category"] as? String)?.lowercased()
        let eventType = normalisedEventType(json["eventType"])

        guard let eventType else { return nil }
        // The third condition is load-bearing: four of the §16 feature events
        // (`HAND_RAISED`, `REQUEST_TO_SPEAK`, `HAND_LOWERED`,
        // `HAND_ACKNOWLEDGED`) carry no `CALL_` prefix, so without it they
        // survive only while the server remembers to set `category` — one
        // missing field would drop the whole feature silently.
        guard category == ChatMqttEvents.Call.category
            || eventType.hasPrefix("CALL_")
            || ChatMqttEvents.Call.featureEventTypes.contains(eventType) else {
            return nil
        }

        let notification = json["notification"] as? [String: Any]
        let ui = json["ui"] as? [String: Any]
        return InboundCallEventDTO(
            eventType: eventType,
            payload: json["payload"] as? [String: Any] ?? [:],
            showsNotification: notification?["show"] as? Bool ?? false,
            isFullScreen: ui?["fullScreen"] as? Bool ?? false,
            suppressNotification: json["suppressNotification"] as? Bool ?? false,
            timestamp: timestamp(from: json["timestamp"]) ?? Date()
        )
    }

    // MARK: - Helpers

    /// Backends have sent both `CALL-INITIATED` and `call_initiated`.
    private static func normalisedEventType(_ raw: Any?) -> String? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        return value.uppercased().replacingOccurrences(of: "-", with: "_")
    }

    private static func timestamp(from raw: Any?) -> Date? {
        if let seconds = raw as? Double {
            // Milliseconds where the value is far past a plausible seconds epoch.
            return Date(timeIntervalSince1970: seconds > 4_000_000_000 ? seconds / 1000 : seconds)
        }
        if let millis = raw as? Int {
            return timestamp(from: Double(millis))
        }
        if let iso = raw as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        }
        return nil
    }
}
