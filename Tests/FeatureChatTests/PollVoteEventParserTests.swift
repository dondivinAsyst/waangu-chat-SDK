import XCTest
@testable import WaanguFeatureChat

/// The backend contract for the vote echo is unspecified, so the parser accepts
/// both plausible shapes — a full option array, or a bare delta — and both event
/// spellings. Confirming the real one later lets a branch be deleted; guessing
/// wrong here would drop every vote silently.
final class PollVoteEventParserTests: XCTestCase {

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    func test_parsesDeltaShape() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": [
                "codeMessage": "poll-1",
                "conversationId": "c1",
                "userId": "u2",
                "optionId": "b"
            ]
        ]))

        XCTAssertEqual(event?.type, "poll_vote")
        XCTAssertEqual(event?.referenceId, "poll-1")
        XCTAssertEqual(event?.conversationId, "c1")
    }

    func test_acceptsTheAlternateEventSpelling() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTE",
            "payload": ["messageId": "poll-1", "userId": "u2", "optionId": "a"]
        ]))

        XCTAssertEqual(event?.type, "poll_vote")
        XCTAssertEqual(event?.referenceId, "poll-1")
    }

    func test_decodesDeltaPayload() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": ["messageId": "poll-1", "senderId": "u3", "optionId": "b"]
        ]))

        let dto = event?.decodePayload(as: InboundPollVoteDTO.self)
        // `messageId` was lifted onto `codeMessage` by the parser, so the DTO
        // never has to know which name it arrived under.
        XCTAssertEqual(dto?.resolvedCodeMessage, "poll-1")
        XCTAssertEqual(dto?.resolvedVoterId, "u3")
        XCTAssertEqual(dto?.resolvedOptionId, "b")
        XCTAssertNil(dto?.pollOptions)
    }

    func test_decodesAuthoritativeOptionArray() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": [
                "codeMessage": "poll-1",
                "userId": "u2",
                "optionId": "a",
                "pollOptions": [
                    ["id": "a", "text": "Pizza", "voterIds": ["u1", "u2"], "voteCount": 2],
                    ["id": "b", "text": "Sushi", "voterIds": [], "voteCount": 0]
                ]
            ]
        ]))

        let dto = event?.decodePayload(as: InboundPollVoteDTO.self)
        XCTAssertEqual(dto?.resolvedCodeMessage, "poll-1")
        XCTAssertEqual(dto?.pollOptions?.count, 2)
        XCTAssertEqual(dto?.pollOptions?.first?.voterIds, ["u1", "u2"])
        XCTAssertEqual(dto?.pollOptions?.first?.voteCount, 2)
    }

    func test_ignoresAVoteWithNoMessageId() {
        XCTAssertNil(ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": ["userId": "u2", "optionId": "a"]
        ])))
    }

    /// A vote must not be mistaken for a message: the message branch would write
    /// a new row rather than patch the poll.
    func test_voteIsNotTreatedAsAMessage() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": ["codeMessage": "poll-1", "userId": "u2", "optionId": "a"]
        ]))

        XCTAssertNotEqual(event?.type, "message")
    }

    // MARK: - selectedOptions (the shape the server actually sends)

    /// The production payload, verbatim. It names the selection
    /// `selectedOptions` — the same name `OutboundVotePollDTO` sends it out
    /// with — and carries no `optionId` at all. Before this was decoded, the
    /// vote reached `applyInboundPollVoteEvent` and died on its empty-optionId
    /// guard: no write, no error, no log.
    func test_decodesTheProductionSelectedOptionsShape() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": [
                "codeMessage": "a92773f7-2891-43da-909a-0ab42a9955aa",
                "conversationId": "d413e4c5-f88f-3a4b-a0ee-93e2904bf561",
                "userId": "611768bb8b70e0c342bedd7b",
                "senderId": "611768bb8b70e0c342bedd7b",
                "selectedOptions": ["002f419e-4dbd-4b97-a44f-400fd7e1676d"],
                "tenantId": "waangu-user",
                "country": NSNull(),
                "votedAt": "2026-09-11T15:51:25.715823Z",
                "eventType": "POLL_VOTED",
                "eventVersion": 1
            ],
            "conversationId": "d413e4c5-f88f-3a4b-a0ee-93e2904bf561",
            "timestamp": "2026-09-11T15:51:27.573Z",
            "processingTimeMs": 2,
            "version": 1
        ]))

        XCTAssertEqual(event?.type, "poll_vote")
        XCTAssertEqual(event?.referenceId, "a92773f7-2891-43da-909a-0ab42a9955aa")
        XCTAssertEqual(event?.conversationId, "d413e4c5-f88f-3a4b-a0ee-93e2904bf561")

        let dto = event?.decodePayload(as: InboundPollVoteDTO.self)
        XCTAssertEqual(dto?.resolvedCodeMessage, "a92773f7-2891-43da-909a-0ab42a9955aa")
        XCTAssertEqual(dto?.resolvedVoterId, "611768bb8b70e0c342bedd7b")
        XCTAssertEqual(dto?.resolvedSelection, ["002f419e-4dbd-4b97-a44f-400fd7e1676d"])
        // No single-option field in this shape — the selection is the only path.
        XCTAssertEqual(dto?.resolvedOptionId, "")
        XCTAssertNil(dto?.pollOptions)
    }

    /// `votedAt` carries six fractional digits; the event time must come from it
    /// rather than silently falling back to the envelope's `timestamp`.
    func test_selectedOptionsShapeTakesItsTimeFromVotedAt() {
        let event = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": [
                "codeMessage": "poll-1",
                "userId": "u2",
                "selectedOptions": ["a"],
                "votedAt": "2026-09-11T15:51:25.715823Z"
            ],
            "timestamp": "2026-09-11T15:51:27.573Z"
        ]))

        // 2026-09-11T15:51:25.715Z, not the envelope's :27.573.
        XCTAssertEqual(event?.at ?? 0, 1789141885.715, accuracy: 0.01)
    }

    /// An empty selection is a retraction and must stay distinguishable from a
    /// payload that names no selection at all — the merger relies on it.
    func test_emptySelectedOptionsIsARetractionNotAnAbsence() {
        let retraction = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": ["codeMessage": "poll-1", "userId": "u2", "selectedOptions": [String]()]
        ]))?.decodePayload(as: InboundPollVoteDTO.self)

        XCTAssertEqual(retraction?.resolvedSelection, [])

        let absent = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": ["codeMessage": "poll-1", "userId": "u2", "optionId": "a"]
        ]))?.decodePayload(as: InboundPollVoteDTO.self)

        XCTAssertNil(absent?.resolvedSelection)
    }

    /// Should both names ever ride the same payload, `optionIds` is the one the
    /// contract documents — it wins.
    func test_optionIdsOutranksSelectedOptions() {
        let dto = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": [
                "codeMessage": "poll-1",
                "userId": "u2",
                "optionIds": ["a"],
                "selectedOptions": ["b"]
            ]
        ]))?.decodePayload(as: InboundPollVoteDTO.self)

        XCTAssertEqual(dto?.resolvedSelection, ["a"])
    }

    /// Multi-select is the whole reason the field is an array.
    func test_decodesAMultipleChoiceSelection() {
        let dto = ChatMqttEventParser.parse(data: json([
            "eventType": "POLL_VOTED",
            "payload": [
                "codeMessage": "poll-1",
                "userId": "u2",
                "selectedOptions": ["a", "b", "c"]
            ]
        ]))?.decodePayload(as: InboundPollVoteDTO.self)

        XCTAssertEqual(dto?.resolvedSelection, ["a", "b", "c"])
    }
}
