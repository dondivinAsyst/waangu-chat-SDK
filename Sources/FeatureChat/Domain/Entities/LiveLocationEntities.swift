import Foundation

// MARK: - Live location

/// A share this device is publishing.
///
/// Persisted, unlike the ticks it produces: an app that is killed mid-share has
/// to know on relaunch that it owes the conversation a `start` and more
/// positions, or the bubble it already sent would sit there claiming to be live
/// while nothing moved it.
struct LiveLocationShareSession: Codable, Equatable, Sendable, Identifiable {
    /// The anchor message's `codeMessage`, which is also the share id.
    let shareId: String
    let conversationId: String
    let codeMessage: String
    let durationMinutes: Int
    let expiresAt: Date

    var id: String { shareId }

    /// True while the share should still be publishing.
    func isActive(asOf now: Date = Date()) -> Bool {
        expiresAt > now
    }
}

/// Announces that a share this device owned has ended, so the room can freeze
/// its bubble. Posted as `.liveLocationShareEnded`.
///
/// A class, as `OutgoingMessageLocallySavedEvent` is: these ride
/// `Notification.object`, which bridges through Objective-C.
final class LiveLocationShareEndedEvent {
    let shareId: String
    let conversationId: String
    /// The last position published, when there was one.
    let latitude: Double?
    let longitude: Double?

    init(shareId: String, conversationId: String, latitude: Double?, longitude: Double?) {
        self.shareId = shareId
        self.conversationId = conversationId
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// How long a share runs. The contract names these four and no others.
enum LiveLocationDuration: Int, CaseIterable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case eightHours = 480

    var minutes: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }

    /// The nearest supported duration to a number of seconds.
    ///
    /// The picker offers its own list of durations and the server accepts only
    /// these, so a value from the UI is snapped rather than sent through and
    /// rejected.
    static func nearest(toSeconds seconds: TimeInterval) -> LiveLocationDuration {
        allCases.min(by: {
            abs($0.seconds - seconds) < abs($1.seconds - seconds)
        }) ?? .fifteenMinutes
    }
}

/// One position of a live location share.
///
/// Deliberately not part of `ChatLocationItem`: the anchor message persists, a
/// tick does not. Ticks arrive on the user inbox as `LIVE_LOCATION_UPDATE`,
/// live in memory for as long as the share runs, and are gone on relaunch —
/// the feed keeps only the `LOCATION` bubble they move.
struct LiveLocationTick: Equatable, Sendable {

    /// Identifies the share across every participant. The sender sets it to the
    /// anchor message's `codeMessage`, so a bubble and its ticks share one id.
    let shareId: String

    let conversationId: String?

    /// Who is sharing. Nil on a payload that omits it — the bubble already
    /// knows its sender, so this is only used when matching ticks to a share.
    let senderId: String?

    let latitude: Double
    let longitude: Double

    /// Horizontal accuracy in metres, when the sender reported one.
    let accuracy: Double?

    /// When the share stops accepting ticks. Nil when the event carried none,
    /// which leaves expiry to the STOP event alone.
    let expiresAt: Date?

    /// When this position was measured.
    let at: Date

    /// False once `LIVE_LOCATION_STOP` has landed, or once `expiresAt` has
    /// passed: the last position stays on the map, the share is over.
    let isLive: Bool

    /// True when `expiresAt` is in the past, measured against `now`.
    ///
    /// Realtime auto-stops an expired share, but that event only reaches a
    /// device that is connected — a receiver coming back from background has
    /// to reach the same conclusion on its own.
    func hasExpired(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    /// The same tick with the share marked finished.
    func stopped() -> LiveLocationTick {
        guard isLive else { return self }
        return LiveLocationTick(
            shareId: shareId,
            conversationId: conversationId,
            senderId: senderId,
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            expiresAt: expiresAt,
            at: at,
            isLive: false
        )
    }
}
