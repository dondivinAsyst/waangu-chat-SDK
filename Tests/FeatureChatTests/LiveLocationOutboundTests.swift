import XCTest
@testable import WaanguFeatureChat

/// The sender's half of a live share: the topics it publishes on, the shape of
/// what it sends, and the session bookkeeping that lets a share survive the app
/// being killed. All of it is asserted against the integration note, since
/// nothing on this device will tell us we got the wire wrong — the ticks would
/// simply be dropped.
final class LiveLocationOutboundTests: XCTestCase {

    private func encoded<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Topics

    func test_topicsMatchTheContract() {
        XCTAssertEqual(
            ChatMQTTTopics.In.liveLocationStart.path,
            "waangu-chat/live-location/start"
        )
        // The only chat traffic outside the `waangu-chat/` tree.
        XCTAssertEqual(
            ChatMQTTTopics.LiveShare.location(shareId: "msg-live-001").path,
            "live-shares/msg-live-001/location"
        )
        XCTAssertEqual(
            ChatMQTTTopics.LiveShare.stop(shareId: "msg-live-001").path,
            "live-shares/msg-live-001/stop"
        )
    }

    // MARK: - Payloads

    func test_startPayloadCarriesTheMappingFields() throws {
        let dto = OutboundLiveLocationStartDTO(
            shareId: "msg-live-001",
            userId: "user-A",
            conversationId: "conv-1",
            codeMessage: "msg-live-001",
            durationMinutes: 15,
            expiresAt: 1_734_567_890_000
        )

        let json = try encoded(dto)
        XCTAssertEqual(json["shareId"] as? String, "msg-live-001")
        XCTAssertEqual(json["userId"] as? String, "user-A")
        XCTAssertEqual(json["conversationId"] as? String, "conv-1")
        XCTAssertEqual(json["codeMessage"] as? String, "msg-live-001")
        XCTAssertEqual(json["durationMinutes"] as? Int, 15)
        XCTAssertEqual(json["expiresAt"] as? Double, 1_734_567_890_000)
    }

    /// `lat`/`lng` on a tick, not `latitude`/`longitude` — the ingress shape
    /// differs from the egress one, and sending the wrong pair fails silently.
    func test_tickPayloadUsesShortCoordinateKeys() throws {
        let dto = OutboundLiveLocationTickDTO(
            shareId: "msg-live-001",
            userId: "user-A",
            lat: 48.857,
            lng: 2.353,
            accuracy: 12,
            timestamp: 1_734_567_800_000,
            expiresAt: 1_734_567_890_000,
            conversationId: nil,
            codeMessage: nil
        )

        let json = try encoded(dto)
        XCTAssertEqual(json["lat"] as? Double, 48.857)
        XCTAssertEqual(json["lng"] as? Double, 2.353)
        XCTAssertEqual(json["accuracy"] as? Double, 12)
        XCTAssertEqual(json["timestamp"] as? Double, 1_734_567_800_000)
        // Absent unless this is the bootstrap tick.
        XCTAssertNil(json["conversationId"])
        XCTAssertNil(json["codeMessage"])
    }

    func test_bootstrapTickCarriesTheConversation() throws {
        let dto = OutboundLiveLocationTickDTO(
            shareId: "msg-live-001",
            userId: "user-A",
            lat: 48.857,
            lng: 2.353,
            accuracy: nil,
            timestamp: 1_734_567_800_000,
            expiresAt: 1_734_567_890_000,
            conversationId: "conv-1",
            codeMessage: "msg-live-001"
        )

        let json = try encoded(dto)
        XCTAssertEqual(json["conversationId"] as? String, "conv-1")
        XCTAssertEqual(json["codeMessage"] as? String, "msg-live-001")
    }

    func test_stopPayloadAllowsNoFinalPosition() throws {
        let dto = OutboundLiveLocationStopDTO(
            shareId: "msg-live-001",
            userId: "user-A",
            lat: nil,
            lng: nil,
            accuracy: nil
        )

        let json = try encoded(dto)
        XCTAssertEqual(json["shareId"] as? String, "msg-live-001")
        XCTAssertNil(json["lat"])
    }

    // MARK: - Duration

    func test_durationSnapsToTheSupportedValues() {
        XCTAssertEqual(LiveLocationDuration.nearest(toSeconds: 15 * 60), .fifteenMinutes)
        XCTAssertEqual(LiveLocationDuration.nearest(toSeconds: 60 * 60), .oneHour)
        XCTAssertEqual(LiveLocationDuration.nearest(toSeconds: 8 * 60 * 60), .eightHours)
        // Anything off-contract lands on the closest allowed value rather than
        // being sent through and rejected.
        XCTAssertEqual(LiveLocationDuration.nearest(toSeconds: 20 * 60), .fifteenMinutes)
        XCTAssertEqual(LiveLocationDuration.nearest(toSeconds: 40 * 60), .thirtyMinutes)
    }

    // MARK: - Session store

    private func makeStore() -> (LiveLocationSessionStore, UserDefaults) {
        let suite = UserDefaults(suiteName: "LiveLocationOutboundTests.\(UUID().uuidString)")!
        return (LiveLocationSessionStore(defaults: suite), suite)
    }

    private func session(
        _ shareId: String,
        expiresIn seconds: TimeInterval = 900
    ) -> LiveLocationShareSession {
        LiveLocationShareSession(
            shareId: shareId,
            conversationId: "conv-1",
            codeMessage: shareId,
            durationMinutes: 15,
            expiresAt: Date().addingTimeInterval(seconds)
        )
    }

    func test_storeKeepsSeveralSharesApart() {
        let (store, _) = makeStore()

        store.upsert(session("a"))
        store.upsert(session("b"))

        XCTAssertEqual(Set(store.load().map(\.shareId)), ["a", "b"])

        store.remove(shareId: "a")
        XCTAssertEqual(store.load().map(\.shareId), ["b"])
    }

    /// The old single `LiveLocationExpiryDate` key held one deadline for the
    /// whole app, so a second share overwrote the first and neither could be
    /// stopped by name.
    func test_storeReplacesAShareRatherThanDuplicatingIt() {
        let (store, _) = makeStore()

        store.upsert(session("a", expiresIn: 900))
        store.upsert(session("a", expiresIn: 1800))

        XCTAssertEqual(store.load().count, 1)
    }

    func test_storeDropsExpiredSharesOnLoad() {
        let (store, _) = makeStore()

        store.upsert(session("live", expiresIn: 900))
        store.upsert(session("over", expiresIn: -60))

        XCTAssertEqual(store.load().map(\.shareId), ["live"])
    }

    func test_unreadablePayloadReadsAsEmpty() {
        let (store, defaults) = makeStore()
        defaults.set(Data("not json".utf8), forKey: "chat.liveLocation.activeShares")

        XCTAssertTrue(store.load().isEmpty)
        // And the bad payload is cleared, so it cannot fail forever.
        XCTAssertNil(defaults.data(forKey: "chat.liveLocation.activeShares"))
    }
}
