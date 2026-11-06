import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// A poll crosses four representations between the composer and the bubble:
/// domain content, wire JSON, the storage blob, and back. Each hop drops
/// anything it does not explicitly carry, so the round trip is the only honest
/// test that the wiring is complete.
final class PollContentCodecTests: XCTestCase {

    private func pollMessage() -> MessageDataItem {
        var content = MessageContent()
        content.poll = PollContent(
            question: "Lunch?",
            options: [
                PollOption(id: "a", text: "Pizza", voterIds: ["u1"], voteCount: 1),
                PollOption(id: "b", text: "Sushi")
            ]
        )
        return OutgoingMessageBuilder.buildOutgoingMessage(
            content: content,
            type: .POLL,
            groupId: nil,
            reply: nil,
            code: "poll-1"
        )
    }

    // MARK: - Outbound

    func test_outgoingContentCarriesThePoll() {
        let dto = MessageContentWireCodec.buildContentDTO(from: pollMessage())

        XCTAssertEqual(dto.pollQuestion, "Lunch?")
        XCTAssertEqual(dto.pollOptions?.count, 2)
        XCTAssertEqual(dto.pollOptions?.first?.id, "a")
        XCTAssertEqual(dto.pollOptions?.first?.text, "Pizza")
        XCTAssertEqual(dto.pollOptions?.first?.voterIds, ["u1"])
        XCTAssertEqual(dto.pollOptions?.first?.voteCount, 1)
        XCTAssertEqual(dto.pollIsMultipleChoice, false)
        XCTAssertEqual(dto.pollIsClosed, false)
    }

    func test_pollSurvivesTheJSONRoundTrip() {
        let encoded = MessageContentWireCodec.encode(from: pollMessage())
        let decoded = MessageContentWireCodec.decode(encoded, typeMessage: "POLL")

        XCTAssertEqual(decoded.pollQuestion, "Lunch?")
        XCTAssertEqual(decoded.pollOptions?.map(\.text), ["Pizza", "Sushi"])
        XCTAssertEqual(decoded.pollOptions?.first?.voterIds, ["u1"])
    }

    func test_nonPollMessageCarriesNoPollFields() {
        let text = OutgoingMessageBuilder.buildOutgoingMessage(
            content: MessageContent(text: "hello"),
            type: .TEXT,
            groupId: nil,
            reply: nil,
            code: "text-1"
        )
        let dto = MessageContentWireCodec.buildContentDTO(from: text)

        XCTAssertNil(dto.pollQuestion)
        XCTAssertNil(dto.pollOptions)
        XCTAssertNil(dto.pollIsMultipleChoice)
        XCTAssertNil(dto.pollIsClosed)
    }

    // MARK: - Inbound

    func test_inboundPollTypeMapsToPoll() {
        XCTAssertEqual(MessageModelMapper.mapInboundType("POLL"), .poll)
    }

    func test_inboundContentCarriesThePoll() {
        let wire = MessageContentWireCodec.decode(
            MessageContentWireCodec.encode(from: pollMessage()),
            typeMessage: "POLL"
        )
        let content = MessageModelMapper.mapInboundContent(
            wire,
            type: .poll,
            fieldCrypto: PassthroughFieldCrypto()
        )

        XCTAssertEqual(content.pollQuestion, "Lunch?")
        XCTAssertEqual(content.pollOptions?.count, 2)
        XCTAssertEqual(content.pollOptions?.first?.voterIds, ["u1"])
        XCTAssertEqual(content.pollOptions?.first?.voteCount, 1)
        XCTAssertEqual(content.pollIsClosed, false)
    }

    /// A count the server omitted is derived from the voters it did name, so a
    /// sparse payload can never render a poll with bars at zero.
    func test_missingVoteCountFallsBackToVoterCount() {
        let wire = MessageContentDTO(
            pollQuestion: "Lunch?",
            pollOptions: [
                PollOptionDTO(id: "a", text: "Pizza", voterIds: ["u1", "u2"], voteCount: nil),
                PollOptionDTO(id: "b", text: "Sushi", voterIds: nil, voteCount: nil)
            ]
        )
        let content = MessageModelMapper.mapInboundContent(
            wire,
            type: .poll,
            fieldCrypto: PassthroughFieldCrypto()
        )

        XCTAssertEqual(content.pollOptions?.first?.voteCount, 2)
        XCTAssertEqual(content.pollOptions?.last?.voterIds, [])
        XCTAssertEqual(content.pollOptions?.last?.voteCount, 0)
    }

    // MARK: - Storage round trip

    func test_storedPollRebuildsForTheUI() {
        let stored = MessageModelMapper.buildContent(
            from: pollMessage(),
            fieldCrypto: PassthroughFieldCrypto()
        )
        let model = MessageModel(
            id: "poll-1",
            conversationId: "c1",
            senderId: "u1",
            senderName: "Ada",
            type: .poll,
            content: stored
        )

        let item = MessageModelMapper.toDomain(model, fieldCrypto: PassthroughFieldCrypto())

        XCTAssertEqual(item.typeMessage, .POLL)
        XCTAssertEqual(item.message.poll?.question, "Lunch?")
        XCTAssertEqual(item.message.poll?.options.map(\.text), ["Pizza", "Sushi"])
        XCTAssertEqual(item.message.poll?.options.first?.voterIds, ["u1"])
        XCTAssertEqual(item.message.poll?.isMultipleChoice, false)
        XCTAssertEqual(item.message.poll?.isClosed, false)
    }

    /// A poll needs a question and two options to be one. Anything less is a
    /// malformed payload, and must fall back to the text renderer rather than
    /// drawing an empty poll.
    func test_pollWithFewerThanTwoOptionsIsNotAPoll() {
        var content = MessageContentModel()
        content.pollQuestion = "Lunch?"
        content.pollOptions = [PollOptionModel(id: "a", text: "Pizza")]

        let model = MessageModel(
            id: "poll-2",
            conversationId: "c1",
            senderId: "u1",
            senderName: "Ada",
            type: .poll,
            content: content
        )

        XCTAssertNil(MessageModelMapper.toDomain(model, fieldCrypto: PassthroughFieldCrypto()).message.poll)
    }

    // MARK: - Change detection

    /// The timeline is diffed with `==`, so a vote that leaves every compared
    /// field untouched renders as no change at all — the bubble keeps its old
    /// bars until the room is rebuilt from scratch. That is true of a vote
    /// arriving from anyone, not just this device.
    func test_aVoteMakesTheMessageUnequal() {
        let before = pollMessage()
        var after = before
        after.message.poll = PollVoteMerger.toggle(
            optionId: "b",
            voterId: "u9",
            in: before.message.poll!
        )

        XCTAssertNotEqual(before, after)
    }

    func test_anUnchangedPollStaysEqual() {
        XCTAssertEqual(pollMessage(), pollMessage())
    }

    func test_pollWithNoQuestionIsNotAPoll() {
        var content = MessageContentModel()
        content.pollOptions = [
            PollOptionModel(id: "a", text: "Pizza"),
            PollOptionModel(id: "b", text: "Sushi")
        ]

        let model = MessageModel(
            id: "poll-3",
            conversationId: "c1",
            senderId: "u1",
            senderName: "Ada",
            type: .poll,
            content: content
        )

        XCTAssertNil(MessageModelMapper.toDomain(model, fieldCrypto: PassthroughFieldCrypto()).message.poll)
    }
}

/// Storage encrypts display names and message text on the way in and decrypts
/// them on the way out. These tests are about what survives the round trip, not
/// about the cipher, so both directions are the identity.
private struct PassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
