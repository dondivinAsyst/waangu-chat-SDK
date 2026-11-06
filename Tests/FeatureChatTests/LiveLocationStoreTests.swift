import Combine
import XCTest
@testable import WaanguFeatureChat

/// The store is the whole persistence story for live location: ticks have a
/// Redis TTL behind them and never reach the database, so everything that keeps
/// a pin honest — ordering, expiry, a stop that carries no position — has to
/// hold here.
final class LiveLocationStoreTests: XCTestCase {

    private let store = LiveLocationStore.shared

    override func setUp() {
        super.setUp()
        store.clearAll()
    }

    override func tearDown() {
        store.clearAll()
        super.tearDown()
    }

    private func tick(
        shareId: String,
        latitude: Double = 48.857,
        longitude: Double = 2.353,
        at: Date = Date(),
        expiresAt: Date? = nil,
        isLive: Bool = true
    ) -> LiveLocationTick {
        LiveLocationTick(
            shareId: shareId,
            conversationId: "conv-1",
            senderId: "user-A",
            latitude: latitude,
            longitude: longitude,
            accuracy: 12,
            expiresAt: expiresAt,
            at: at,
            isLive: isLive
        )
    }

    func test_keepsTheLatestPosition() {
        let now = Date()
        store.apply(tick(shareId: "s1", latitude: 1, at: now))
        store.apply(tick(shareId: "s1", latitude: 2, at: now.addingTimeInterval(5)))

        XCTAssertEqual(store.tick(for: "s1")?.latitude, 2)
    }

    /// MQTT gives no ordering guarantee across a reconnect, and a stale tick
    /// arriving late would drag the pin backwards.
    func test_ignoresOutOfOrderTick() {
        let now = Date()
        store.apply(tick(shareId: "s2", latitude: 2, at: now))
        store.apply(tick(shareId: "s2", latitude: 1, at: now.addingTimeInterval(-5)))

        XCTAssertEqual(store.tick(for: "s2")?.latitude, 2)
    }

    /// Realtime auto-stops an expired share, but that only reaches a device
    /// that is connected — expiry has to be concluded locally too.
    func test_storesExpiredTickAsStopped() {
        store.apply(tick(shareId: "s3", expiresAt: Date().addingTimeInterval(-60)))

        let stored = store.tick(for: "s3")
        XCTAssertNotNil(stored)
        XCTAssertFalse(stored?.isLive ?? true)
    }

    func test_readingAppliesExpiryThatPassedAfterTheTickLanded() {
        store.apply(tick(shareId: "s4", expiresAt: Date().addingTimeInterval(0.05)))
        XCTAssertTrue(store.tick(for: "s4")?.isLive ?? false)

        // The share ends while nothing new arrives.
        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertFalse(store.tick(for: "s4")?.isLive ?? true)
    }

    func test_markStoppedKeepsLastPositionAndEndsShare() {
        store.apply(tick(shareId: "s5", latitude: 9))
        store.markStopped(shareId: "s5")

        let stored = store.tick(for: "s5")
        XCTAssertEqual(stored?.latitude, 9)
        XCTAssertFalse(stored?.isLive ?? true)
    }

    /// A stop for a share this device never saw a tick for has no pin to
    /// freeze — the anchor bubble already holds the position the feed shows.
    func test_markStoppedOnUnknownShareStoresNothing() {
        store.markStopped(shareId: "s6")

        XCTAssertNil(store.tick(for: "s6"))
    }

    func test_publishesEveryAcceptedChange() {
        var received: [LiveLocationTick] = []
        let cancellable = store.updates.sink { received.append($0) }
        defer { cancellable.cancel() }

        let now = Date()
        store.apply(tick(shareId: "s7", latitude: 1, at: now))
        store.apply(tick(shareId: "s7", latitude: 0, at: now.addingTimeInterval(-10)))
        store.markStopped(shareId: "s7")

        // The out-of-order tick was dropped, so only the first and the stop.
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.first?.latitude, 1)
        XCTAssertFalse(received.last?.isLive ?? true)
    }
}
