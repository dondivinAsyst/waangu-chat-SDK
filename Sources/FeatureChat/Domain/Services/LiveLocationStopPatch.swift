import Foundation

/// Applies the end of a live share to the anchor message's stored content.
///
/// Extracted from `ChatSyncDelegate` for the same reason `PollVoteMerger` is:
/// the interesting part is the rule, not the fetch and the save around it, and
/// the rule is what has to keep working when a bubble is read back after a
/// relaunch.
enum LiveLocationStopPatch {

    /// Returns the patched content, or nil when there is nothing to patch.
    ///
    /// `isLiveLocation` stays true: the bubble has to keep saying it *was* a
    /// live share so it can say the share ended. The deadline is what marks it
    /// over, which is the same thing an ordinary expiry does — one rule, so a
    /// share that ends by stopping and a share that ends by running out are
    /// read back identically.
    ///
    /// - Parameters:
    ///   - content: the anchor message's stored content.
    ///   - endedAt: when the stop happened, in epoch seconds.
    ///   - latitude: final position, when the stop carried one.
    ///   - longitude: final position, when the stop carried one.
    static func apply(
        to content: MessageContentModel,
        endedAt: Double,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> MessageContentModel? {
        // Not a live share, or one already ended: nothing to record. Patching
        // anyway would rewrite the message on every duplicate stop the broker
        // redelivers.
        guard content.isLiveLocation == true else { return nil }
        if let existing = content.liveExpiresAt, existing <= endedAt {
            return nil
        }

        var patched = content
        // Never later than the deadline it already had — a stop that arrives
        // after the share expired must not revive it for those seconds.
        patched.liveExpiresAt = min(content.liveExpiresAt ?? endedAt, endedAt)

        if let latitude, let longitude {
            patched.latitude = latitude
            patched.longitude = longitude
        }

        return patched
    }
}
