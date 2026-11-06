import Combine
import Foundation

/// In-memory cache of the latest position of every live location share.
///
/// Ephemeral by contract: ticks ride Realtime with a Redis TTL behind them and
/// are never projected into the feed, so nothing here is written to the
/// database. A relaunch starts empty and the map falls back to the anchor
/// message's position until the next tick lands.
///
/// Shaped after `UserPresenceStore` — same lock, same singleton — with a
/// publisher added because the map has to move as ticks arrive, where presence
/// is only ever read on demand.
final class LiveLocationStore: @unchecked Sendable {
    static let shared = LiveLocationStore()

    private let lock = NSLock()
    private var byShareId: [String: LiveLocationTick] = [:]
    private let subject = PassthroughSubject<LiveLocationTick, Never>()

    /// Emits the stored tick after every accepted change, stops included.
    ///
    /// Delivered on whichever thread the inbox pump is running, so observers
    /// that drive UI must hop to the main queue themselves.
    var updates: AnyPublisher<LiveLocationTick, Never> {
        subject.eraseToAnyPublisher()
    }

    private init() {}

    /// Records a position for a share.
    ///
    /// Out-of-order ticks are dropped: MQTT gives no ordering guarantee across
    /// reconnects, and a stale position arriving late would drag the pin
    /// backwards. A tick that arrives after `expiresAt` is stored as a stop —
    /// Realtime's own auto-stop may never reach a device that was offline.
    func apply(_ tick: LiveLocationTick) {
        let resolved = tick.hasExpired() ? tick.stopped() : tick

        lock.lock()
        if let existing = byShareId[resolved.shareId], existing.at > resolved.at {
            lock.unlock()
            return
        }
        byShareId[resolved.shareId] = resolved
        lock.unlock()

        subject.send(resolved)
    }

    /// Ends a share that carried no final position, keeping the last one known.
    ///
    /// A STOP for a share this device never saw a tick for is nothing to
    /// record: there is no pin to freeze, and the anchor bubble already holds
    /// the position the feed shows.
    func markStopped(shareId: String) {
        lock.lock()
        guard let existing = byShareId[shareId], existing.isLive else {
            lock.unlock()
            return
        }
        let stopped = existing.stopped()
        byShareId[shareId] = stopped
        lock.unlock()

        subject.send(stopped)
    }

    /// The latest position for a share, with expiry already applied so a
    /// caller never sees a share still marked live past its deadline.
    func tick(for shareId: String) -> LiveLocationTick? {
        lock.lock()
        defer { lock.unlock() }
        guard let tick = byShareId[shareId] else { return nil }
        return tick.hasExpired() ? tick.stopped() : tick
    }

    /// Drops everything — sign-out, or an account switch.
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        byShareId.removeAll()
    }
}
