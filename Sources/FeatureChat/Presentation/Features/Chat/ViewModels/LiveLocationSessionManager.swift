import CoreLocation
import Foundation

/// Publishes this device's live location shares.
///
/// Shared rather than owned by a chat room: a share outlives the room it
/// started in, and the whole point is that it keeps publishing while the user
/// is elsewhere in the app — or has it backgrounded.
///
/// Ticks are driven by a clock, not by movement. A sender standing still is
/// still sharing, and a watcher who stops seeing positions has no way to tell
/// "not moving" from "connection dropped"; a steady 4-second heartbeat answers
/// that. Movement only refreshes what the next tick will carry.
final class LiveLocationSessionManager: NSObject, ObservableObject {

    static let shared = LiveLocationSessionManager()

    /// Shares currently publishing from this device.
    @Published private(set) var activeShares: [LiveLocationShareSession] = []

    /// Between 3 and 5 seconds, per the integration note.
    private static let tickInterval: TimeInterval = 4

    private let locationManager = CLLocationManager()
    private var store: LiveLocationSessionStoring?
    private var publisher: PublishLiveLocationUseCaseProtocol?
    private var ticker: Timer?
    private var lastLocation: CLLocation?

    /// Shares whose `start` has not been confirmed as published, so their next
    /// tick carries the conversation and message id Realtime needs to bootstrap
    /// the share on its own.
    private var awaitingBootstrap: Set<String> = []

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    /// Hands the manager the way to publish, and where to persist.
    ///
    /// Both come from outside because this outlives every room: the use case is
    /// built with the chat container, and the store is a local data source that
    /// presentation has no business constructing. `ChatFeature` passes both at
    /// bootstrap; a room passes only the publisher.
    func configure(
        publisher: PublishLiveLocationUseCaseProtocol,
        sessionStore: LiveLocationSessionStoring? = nil
    ) {
        self.publisher = publisher
        if let sessionStore {
            self.store = sessionStore
        }
    }

    // MARK: - Queries

    /// The share running in a conversation, if any. One share per conversation:
    /// a second would put two live bubbles in the same thread with no way for
    /// the reader to tell which is current.
    func activeShare(in conversationId: String) -> LiveLocationShareSession? {
        activeShares.first { $0.conversationId == conversationId && $0.isActive() }
    }

    func isSharing(shareId: String) -> Bool {
        activeShares.contains { $0.shareId == shareId && $0.isActive() }
    }

    // MARK: - Lifecycle

    /// Starts publishing for a share whose anchor message has already been sent.
    ///
    /// Publishing `start` first is what makes Realtime accept the ticks; the
    /// first tick carries the bootstrap fields anyway, so a lost start costs
    /// nothing.
    func start(_ session: LiveLocationShareSession) {
        guard session.isActive() else { return }

        activeShares.removeAll { $0.shareId == session.shareId }
        activeShares.append(session)
        store?.upsert(session)
        awaitingBootstrap.insert(session.shareId)

        beginUpdatingLocation()

        Task { [publisher] in
            await publisher?.start(
                shareId: session.shareId,
                conversationId: session.conversationId,
                codeMessage: session.codeMessage,
                durationMinutes: session.durationMinutes,
                expiresAt: session.expiresAt
            )
        }

        scheduleTicker()
    }

    /// Ends a share and tells the room, carrying the last position we have.
    func stop(shareId: String) {
        guard let index = activeShares.firstIndex(where: { $0.shareId == shareId }) else {
            // Still worth removing from disk: a share can be stopped from a
            // bubble after a relaunch that never resumed it.
            store?.remove(shareId: shareId)
            return
        }

        let share = activeShares.remove(at: index)
        store?.remove(shareId: shareId)
        awaitingBootstrap.remove(shareId)

        let location = lastLocation
        Task { [publisher] in
            await publisher?.stop(
                shareId: shareId,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude,
                accuracy: location?.horizontalAccuracy
            )
        }

        // Our own bubble hears nothing from the server — the fanout excludes
        // the sender — so both halves of "it ended" are announced here: the
        // store for the live pin, the notification for the durable message.
        LiveLocationStore.shared.markStopped(shareId: shareId)
        NotificationCenter.default.post(
            name: .liveLocationShareEnded,
            object: LiveLocationShareEndedEvent(
                shareId: shareId,
                conversationId: share.conversationId,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude
            )
        )

        stopIfIdle()
    }

    /// Stops every share — sign-out, or an account switch.
    func stopAll() {
        for share in activeShares {
            stop(shareId: share.shareId)
        }
    }

    /// Picks up shares that were still running when the app was last killed.
    ///
    /// The feed already holds their anchor bubbles, saying live. Without this
    /// they would keep saying it while nothing published a position — a lie
    /// that lasts until the deadline.
    func resumeStoredShares() {
        let stored = store?.load() ?? []
        guard !stored.isEmpty else { return }

        for session in stored where !isSharing(shareId: session.shareId) {
            start(session)
        }
    }

    // MARK: - Ticking

    private func scheduleTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.publishTick()
        }
        // `.common` so the ticks keep going while a list is being scrolled.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func publishTick() {
        expireFinishedShares()

        guard let location = lastLocation, !activeShares.isEmpty else { return }

        for share in activeShares {
            let bootstrap = awaitingBootstrap.contains(share.shareId)
                ? (conversationId: share.conversationId, codeMessage: share.codeMessage)
                : nil
            awaitingBootstrap.remove(share.shareId)

            Task { [publisher] in
                await publisher?.tick(
                    shareId: share.shareId,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    accuracy: location.horizontalAccuracy,
                    expiresAt: share.expiresAt,
                    bootstrap: bootstrap
                )
            }

            // Mirrored into the same store the receivers' ticks land in, so the
            // sender's own bubble follows them exactly as a watcher's does.
            // The server never echoes our ticks back to us.
            LiveLocationStore.shared.apply(
                LiveLocationTick(
                    shareId: share.shareId,
                    conversationId: share.conversationId,
                    senderId: nil,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    accuracy: location.horizontalAccuracy,
                    expiresAt: share.expiresAt,
                    at: location.timestamp,
                    isLive: true
                )
            )
        }
    }

    /// Stops any share that has reached its deadline.
    ///
    /// Realtime auto-stops an expired share on its side, but the sender still
    /// owes the room an explicit stop — and this is also what takes the finished
    /// share off disk so a relaunch does not resume it.
    private func expireFinishedShares() {
        let expired = activeShares.filter { !$0.isActive() }
        for share in expired {
            stop(shareId: share.shareId)
        }
    }

    // MARK: - Location

    private func beginUpdatingLocation() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            // Only `always` may keep updating in the background, and setting
            // this without it throws.
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        case .authorizedWhenInUse:
            // Foreground-only sharing still works; it simply stops publishing
            // when the app is not in front.
            break
        default:
            return
        }

        locationManager.startUpdatingLocation()
    }

    private func stopIfIdle() {
        guard activeShares.isEmpty else { return }
        ticker?.invalidate()
        ticker = nil
        locationManager.stopUpdatingLocation()
        if locationManager.authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = false
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LiveLocationSessionManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("[LiveLocationSessionManager] location error: \(error.localizedDescription)")
        #endif
    }

    /// Permission can be granted after a share has already started — the user
    /// answers the prompt while the anchor message is in flight.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !activeShares.isEmpty else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdatingLocation()
        case .denied, .restricted:
            // Nothing can be published any more, and a bubble that says live
            // while the OS refuses to give a position is worse than an ended one.
            stopAll()
        default:
            break
        }
    }
}
