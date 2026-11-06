import Combine
import Foundation

/// Follows one live location share for the views that draw it.
///
/// The bubble and the full-screen viewer both need the same three answers —
/// where the pin is now, whether the share is still running, and how long it
/// has left — and neither should be reaching into `LiveLocationStore` or
/// running its own clock. Ticks arrive on the MQTT thread; everything this
/// publishes is delivered on main.
final class LiveLocationTracker: ObservableObject {

    /// Latest position received for this share.
    ///
    /// Nil until the first tick lands, which is the normal state right after a
    /// share starts and after any relaunch — ticks are never persisted, so the
    /// anchor message's own position stands in until the next one arrives.
    @Published private(set) var tick: LiveLocationTick?

    /// True while the share is running: the sender marked it live, no stop has
    /// landed, and the deadline has not passed.
    @Published private(set) var isLive: Bool = false

    /// Seconds left before the share expires, recomputed once a second. Nil
    /// when the share has no deadline, or is already over.
    @Published private(set) var remaining: TimeInterval?

    private let shareId: String
    private let expiresAt: Date?
    private let declaredLive: Bool
    private let store: LiveLocationStore
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - shareId: the share to follow — the anchor message's `codeMessage`
    ///     unless the sender named a different one.
    ///   - expiresAt: the deadline the anchor message declared, if any.
    ///   - declaredLive: what the anchor message said. A stop that arrives
    ///     later overrides it; so does the deadline passing.
    init(
        shareId: String,
        expiresAt: Date?,
        declaredLive: Bool,
        store: LiveLocationStore = .shared
    ) {
        self.shareId = shareId
        self.expiresAt = expiresAt
        self.declaredLive = declaredLive
        self.store = store
    }

    /// Begins following the share. Safe to call again — a second call is a no-op
    /// while the first is still running, which matters because a bubble can
    /// reappear without ever having gone away.
    func start() {
        guard cancellables.isEmpty else { return }

        tick = store.tick(for: shareId)
        refresh()

        store.updates
            .filter { [shareId] in $0.shareId == shareId }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tick in
                guard let self else { return }
                self.tick = tick
                self.refresh()
            }
            .store(in: &cancellables)

        // Only worth a clock while there is a deadline to count towards.
        guard expiresAt != nil else { return }
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    /// `m:ss` under an hour, `h:mm:ss` over — the shortest form that stays
    /// unambiguous, given a share runs for anything from 15 minutes to 8 hours.
    static func countdown(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Recomputes what the views read, from the last tick and the clock.
    ///
    /// A stop may never arrive — the sender can lose connectivity mid-share —
    /// so the deadline has the final say on whether this is still live.
    private func refresh() {
        let now = Date()

        if let expiresAt {
            let left = expiresAt.timeIntervalSince(now)
            remaining = left > 0 ? left : nil
        } else {
            remaining = nil
        }

        let stoppedByEvent = tick.map { !$0.isLive } ?? false
        // No deadline reads as ended, matching `ChatLocationItem.isLiveActive`:
        // every share the contract can express carries one, so a share without
        // one is a share whose end we simply failed to record.
        let running = expiresAt.map { $0 > now } ?? false
        let live = declaredLive && !stoppedByEvent && running

        if isLive != live { isLive = live }
    }
}
