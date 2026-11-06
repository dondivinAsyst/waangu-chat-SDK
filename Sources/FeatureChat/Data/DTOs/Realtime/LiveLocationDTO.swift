import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: Outbound — start / tick / stop
// ─────────────────────────────────────────────────────────────

/// Published to `waangu-chat/live-location/start`, once, after the anchor
/// message is acknowledged.
///
/// This is what maps the share to its conversation in Redis. Realtime drops a
/// tick for a share it has never seen, so this has to land first — and a start
/// whose `expiresAt` has already passed is ignored outright.
struct OutboundLiveLocationStartDTO: Codable, Sendable, Equatable {
    let shareId: String
    let userId: String
    let conversationId: String
    let codeMessage: String
    let durationMinutes: Int
    /// Epoch millis.
    let expiresAt: Double
}

/// Published to `live-shares/{shareId}/location` every few seconds.
///
/// Deliberately not written to the outbox, unlike every durable message: a tick
/// replayed after a reconnect would put the pin somewhere the sender left
/// minutes ago. A position that missed its moment is better lost than wrong.
struct OutboundLiveLocationTickDTO: Codable, Sendable, Equatable {
    let shareId: String
    let userId: String
    let lat: Double
    let lng: Double
    let accuracy: Double?
    /// Epoch millis — when this position was measured.
    let timestamp: Double
    /// Epoch millis.
    let expiresAt: Double

    /// Carried on the first tick so Realtime can bootstrap a share whose start
    /// was lost, rather than dropping every position that follows it.
    let conversationId: String?
    let codeMessage: String?
}

/// Published to `live-shares/{shareId}/stop`, with the final position when one
/// is known.
struct OutboundLiveLocationStopDTO: Codable, Sendable, Equatable {
    let shareId: String
    let userId: String
    let lat: Double?
    let lng: Double?
    let accuracy: Double?
}

// ─────────────────────────────────────────────────────────────
// MARK: Inbound — live location tick / stop
// ─────────────────────────────────────────────────────────────

/// A `LIVE_LOCATION_UPDATE` or `LIVE_LOCATION_STOP` fanned out to the room.
///
/// Both events carry the same shape; only the position is optional, because a
/// stop may simply end the share and leave the last known pin in place.
///
/// The wire is looser than this: the egress contract nests the position under
/// `location` while a tick republished from its ingress shape carries flat
/// `lat` / `lng`, and `expiresAt` may arrive as epoch millis or as a string.
/// `ChatMqttEventParser` normalises all of that before this decodes, the same
/// way it lifts `emoji` onto `reaction` for a reaction event — so this type
/// only ever sees one shape.
struct InboundLiveLocationDTO: Decodable, Sendable {

    struct Position: Decodable, Sendable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double?
    }

    let shareId: String
    let codeMessage: String?
    let conversationId: String?
    let senderId: String?
    let location: Position?

    /// Epoch **seconds** — the parser converts the millis the wire uses.
    let expiresAt: Double?
}
