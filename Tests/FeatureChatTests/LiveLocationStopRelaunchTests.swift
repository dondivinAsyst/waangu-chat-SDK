import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// What a watcher sees after closing the app.
///
/// Ticks live in memory and are gone on relaunch, so the stored anchor message
/// is the only thing left that knows whether a share is over. This walks the
/// whole chain that has to carry that fact — inbox JSON, parser, DTO, the patch
/// applied to storage, and the bubble built back out of it.
final class LiveLocationStopRelaunchTests: XCTestCase {

    private let sentAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let duration: TimeInterval = 900

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func liveAnchor(shareId: String = "msg-live-001") -> MessageModel {
        MessageModel(
            id: shareId,
            conversationId: "c1",
            senderId: "u1",
            senderName: "Ada",
            type: .location,
            content: MessageContentModel(
                latitude: 48.8566,
                longitude: 2.3522,
                liveDurationSeconds: Int(duration),
                isLiveLocation: true,
                liveShareId: shareId,
                liveExpiresAt: sentAt.addingTimeInterval(duration).timeIntervalSince1970
            ),
            timestamp: sentAt
        )
    }

    /// Parses a `LIVE_LOCATION_STOP` off the inbox the way the delegate does.
    private func stopEvent(
        at stoppedAt: Date,
        position: (lat: Double, lng: Double)? = nil,
        shareId: String = "msg-live-001"
    ) throws -> (event: ChatSyncEventDTO, dto: InboundLiveLocationDTO) {
        var payload: [String: Any] = [
            "shareId": shareId,
            "conversationId": "c1",
            "timestamp": stoppedAt.timeIntervalSince1970 * 1000
        ]
        if let position {
            payload["location"] = ["latitude": position.lat, "longitude": position.lng]
        }

        let event = try XCTUnwrap(ChatMqttEventParser.parse(data: json([
            "eventType": "LIVE_LOCATION_STOP",
            "payload": payload
        ])))
        XCTAssertEqual(event.type, "live_location_stop")
        return (event, try XCTUnwrap(event.decodePayload(as: InboundLiveLocationDTO.self)))
    }

    private func patched(_ model: MessageModel, with stop: (event: ChatSyncEventDTO, dto: InboundLiveLocationDTO)) -> MessageContentModel? {
        LiveLocationStopPatch.apply(
            to: model.content,
            endedAt: stop.event.at,
            latitude: stop.dto.location?.latitude,
            longitude: stop.dto.location?.longitude
        )
    }

    // MARK: - The reported bug

    /// Before the stop was persisted, this is the case that came back live: the
    /// share ended two minutes in, the app was killed, and the anchor still had
    /// thirteen minutes left on a deadline nothing had moved.
    func test_stopSurvivesARelaunch() throws {
        var stored = liveAnchor()
        let stoppedAt = sentAt.addingTimeInterval(120)

        let running = MessageModelMapper.toDomain(stored, fieldCrypto: StopPatchPassthroughCrypto())
        XCTAssertTrue(
            running.message.location?.isLiveActive(asOf: sentAt.addingTimeInterval(60)) == true
        )

        let stop = try stopEvent(at: stoppedAt, position: (48.860, 2.360))
        stored.content = try XCTUnwrap(patched(stored, with: stop))

        // Relaunch: nothing in memory, only what storage holds.
        let ended = MessageModelMapper.toDomain(stored, fieldCrypto: StopPatchPassthroughCrypto())

        XCTAssertFalse(
            ended.message.location?.isLiveActive(asOf: stoppedAt.addingTimeInterval(1)) == true
        )
        // Still a live share, so the bubble can say the share *ended* rather
        // than turning back into an ordinary pin.
        XCTAssertEqual(ended.message.location?.isLive, true)
        // And frozen at the position the stop carried.
        XCTAssertEqual(ended.message.location?.coords.lat, 48.860)
        XCTAssertEqual(ended.message.location?.coords.lng, 2.360)
    }

    func test_stopWithoutAPositionKeepsTheLastKnownOne() throws {
        var stored = liveAnchor()
        let stop = try stopEvent(at: sentAt.addingTimeInterval(120))

        stored.content = try XCTUnwrap(patched(stored, with: stop))

        let ended = MessageModelMapper.toDomain(stored, fieldCrypto: StopPatchPassthroughCrypto())
        XCTAssertEqual(ended.message.location?.coords.lat, 48.8566)
        XCTAssertFalse(ended.message.location?.isLiveActive(asOf: Date()) == true)
    }

    // MARK: - Stops that must change nothing

    /// A stop delivered after the share had already run out. Applying it would
    /// push the deadline *forward*, reviving the share for those seconds.
    func test_stopAfterExpiryDoesNotRevive() throws {
        let stored = liveAnchor()
        let stop = try stopEvent(at: sentAt.addingTimeInterval(duration + 100))

        XCTAssertNil(patched(stored, with: stop))
    }

    /// Brokers redeliver. A second copy of the same stop must not rewrite the
    /// message again.
    func test_duplicateStopIsNotReapplied() throws {
        var stored = liveAnchor()
        let stop = try stopEvent(at: sentAt.addingTimeInterval(120))

        stored.content = try XCTUnwrap(patched(stored, with: stop))
        XCTAssertNil(patched(stored, with: stop))
    }

    func test_pinnedLocationIsNeverPatched() throws {
        var pinned = liveAnchor(shareId: "msg-pin-1")
        pinned.content.isLiveLocation = nil
        pinned.content.liveExpiresAt = nil

        let stop = try stopEvent(at: sentAt.addingTimeInterval(120), shareId: "msg-pin-1")
        XCTAssertNil(patched(pinned, with: stop))
    }
}

private struct StopPatchPassthroughCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
