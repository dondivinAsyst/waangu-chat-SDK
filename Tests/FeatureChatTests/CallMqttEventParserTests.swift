import XCTest
@testable import WaanguFeatureChat

/// The call inbox is shared with chat and stories, so the parser's first job is
/// rejecting everything that is not a call. A false positive here would let chat
/// traffic drive the call state machine.
final class CallMqttEventParserTests: XCTestCase {

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Filtering

    func test_ignoresNonCallCategories() {
        let message = json([
            "eventType": "MESSAGE_SENT",
            "category": "message",
            "payload": ["messageId": "m1"]
        ])
        XCTAssertNil(CallMqttEventParser.parse(data: message))
    }

    func test_ignoresPayloadsWithoutAnEventType() {
        XCTAssertNil(CallMqttEventParser.parse(data: json(["category": "call"])))
    }

    func test_acceptsCallCategory() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_INITIATED",
            "category": "call",
            "payload": ["roomId": "room-1"]
        ]))
        XCTAssertEqual(event?.eventType, "CALL_INITIATED")
        XCTAssertEqual(event?.roomId, "room-1")
    }

    /// Some events arrive without `category` but with a CALL_* type.
    func test_acceptsCallPrefixWithoutCategory() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_ENDED",
            "payload": ["roomId": "room-9"]
        ]))
        XCTAssertEqual(event?.eventType, "CALL_ENDED")
    }

    func test_normalisesEventTypeCasingAndSeparators() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "call-media-answer",
            "category": "call",
            "payload": [:]
        ]))
        XCTAssertEqual(event?.eventType, "CALL_MEDIA_ANSWER")
    }

    // MARK: - Envelope flags

    func test_readsNotificationAndUiFlags() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_INITIATED",
            "category": "call",
            "payload": ["roomId": "r"],
            "notification": ["show": true, "priority": "high"],
            "ui": ["fullScreen": true, "minimizable": false],
            "suppressNotification": false
        ]))

        XCTAssertEqual(event?.showsNotification, true)
        XCTAssertEqual(event?.isFullScreen, true)
        XCTAssertEqual(event?.suppressNotification, false)
    }

    /// Silent signaling must be flagged so it never reaches the UI.
    func test_readsSuppressNotification() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_NEW_PRODUCER",
            "category": "call",
            "payload": [:],
            "suppressNotification": true
        ]))
        XCTAssertEqual(event?.suppressNotification, true)
    }

    func test_defaultsFlagsWhenAbsent() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_PONG",
            "category": "call",
            "payload": [:]
        ]))
        XCTAssertEqual(event?.showsNotification, false)
        XCTAssertEqual(event?.isFullScreen, false)
        XCTAssertEqual(event?.suppressNotification, false)
    }

    // MARK: - Payload accessors

    func test_readsCallerFromParticipants() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_INITIATED",
            "category": "call",
            "payload": [
                "roomId": "room-1",
                "callId": "call-1",
                "from": "userA",
                "type": "video",
                "participants": [
                    ["userId": "userB", "username": "Bob", "phone": "+243222"],
                    ["userId": "userA", "username": "Alice", "phone": "+243111"]
                ]
            ]
        ]))

        XCTAssertEqual(event?.isVideo, true)
        XCTAssertEqual(event?.callId, "call-1")
        XCTAssertEqual(event?.participants.count, 2)
        // `from` picks the caller out of the list, not simply the first entry.
        XCTAssertEqual(event?.caller?.userId, "userA")
        XCTAssertEqual(event?.caller?.username, "Alice")
    }

    func test_audioCallIsNotVideo() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_INITIATED",
            "category": "call",
            "payload": ["roomId": "r", "type": "audio"]
        ]))
        XCTAssertEqual(event?.isVideo, false)
    }

    func test_skipsParticipantsWithoutAUserId() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_PEER_JOINED",
            "category": "call",
            "payload": [
                "roomId": "r",
                "participants": [
                    ["username": "No id"],
                    ["userId": "userC", "username": "Carla"]
                ]
            ]
        ]))
        XCTAssertEqual(event?.participants.map(\.userId), ["userC"])
    }

    // MARK: - Timestamps

    func test_readsMillisecondTimestamps() {
        let millis = 1_800_000_000_000.0
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_ENDED",
            "category": "call",
            "payload": [:],
            "timestamp": millis
        ]))
        XCTAssertEqual(event?.timestamp.timeIntervalSince1970 ?? 0, millis / 1000, accuracy: 1)
    }

    func test_readsIsoTimestamps() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_ENDED",
            "category": "call",
            "payload": [:],
            "timestamp": "2026-07-29T12:00:00.000Z"
        ]))
        XCTAssertNotNil(event?.timestamp)
        XCTAssertNotEqual(event?.timestamp.timeIntervalSince1970, 0)
    }

    // MARK: - Conference features (§16)

    /// Feature events have no `CALL_` prefix, so they survive only while the
    /// server sets `category`. One missing field would silently drop the whole
    /// feature, so the known types are accepted on their own.
    func test_acceptsFeatureEventWithoutCategory() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "HAND_RAISED",
            "payload": ["roomId": "room-1", "participantId": "userB"]
        ]))
        XCTAssertEqual(event?.eventType, "HAND_RAISED")
    }

    func test_acceptsReactionWithCategory() {
        let event = CallMqttEventParser.parse(data: json([
            "eventType": "CALL_REACTION",
            "category": "call",
            "payload": ["roomId": "room-1", "peerId": "userA", "reaction": "👏"]
        ]))
        XCTAssertEqual(event?.eventType, "CALL_REACTION")
    }

    func test_stillIgnoresUnknownPrefixlessEvents() {
        XCTAssertNil(CallMqttEventParser.parse(data: json([
            "eventType": "ORDER_SHIPPED",
            "payload": ["roomId": "room-1"]
        ])))
    }
}
