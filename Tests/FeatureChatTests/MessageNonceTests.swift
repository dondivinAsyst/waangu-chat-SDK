//
//  MessageNonceTests.swift
//  FeatureChatTests
//
//  `send-message` carries a `nonce`: a new lowercase UUID on every send attempt,
//  retries included, while `codeMessage` stays the same. It is never stored.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class MessageNonceTests: XCTestCase {

    private func dto(_ code: String = "code-\(UUID().uuidString)") -> OutboundMessageDTO {
        OutboundMessageDTO(
            sessionId: "s", senderId: "me", senderName: "Me", senderPhone: "+25700000000",
            senderAvatar: nil, receiverId: "peer", groupId: nil, conversationId: "conv",
            codeMessage: code, content: "{}", typeMessage: "TEXT", status: "PENDING",
            forwarded: false, isMoney: false)
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func isLowercaseUUID(_ value: String?) -> Bool {
        guard let value, UUID(uuidString: value) != nil else { return false }
        return value == value.lowercased()
    }

    // MARK: One attempt, one nonce

    func test_eachAttempt_getsANewLowercaseUUID_andKeepsTheCodeMessage() {
        let message = dto("same-code")
        let first = message.withFreshNonce()
        let second = message.withFreshNonce()

        XCTAssertTrue(isLowercaseUUID(first.nonce))
        XCTAssertTrue(isLowercaseUUID(second.nonce))
        XCTAssertNotEqual(first.nonce, second.nonce)
        XCTAssertEqual(first.codeMessage, "same-code")
        XCTAssertEqual(second.codeMessage, "same-code")
    }

    func test_theNonce_isSentUnderTheKey_nonce() throws {
        let body = try JSONEncoder().encode(dto().withFreshNonce())
        XCTAssertTrue(isLowercaseUUID(try json(body)["nonce"] as? String))
    }

    // MARK: Never stored

    func test_theOutbox_storesTheMessage_withoutANonce() throws {
        let item = ChatOutboxItem.sendMessage(dto().withFreshNonce())
        XCTAssertNil(try json(item.payload)["nonce"], "the nonce belongs to one attempt, not to the stored message")
    }

    func test_aMessageQueuedBeforeThisChange_stillDecodes() throws {
        let stored = try dto("old").withoutNonce().toJSONData()
        let decoded = try JSONDecoder().decode(OutboundMessageDTO.self, from: stored)
        XCTAssertEqual(decoded.codeMessage, "old")
        XCTAssertNil(decoded.nonce)
    }

    // MARK: First send and retries

    func test_theFirstSend_publishesANonce_andQueuesTheMessageWithoutOne() async throws {
        let outbox = RecordingChatOutbox()
        let realtime = RecordingRealtimeClient()
        let message = MessageDataItem(codeMessage: "first-send", message: MessageContent(text: "hi"), createdAt: Date())

        await OutgoingMessagePublisher.publish(
            message: message, conversationId: "conv", recipientId: "peer",
            outbox: outbox, realtime: realtime)

        let published = try json(try XCTUnwrap(realtime.publishedBodies.first))
        XCTAssertTrue(isLowercaseUUID(published["nonce"] as? String))
        XCTAssertEqual(published["codeMessage"] as? String, "first-send")

        let queued = try json(try XCTUnwrap(outbox.items.first).payload)
        XCTAssertNil(queued["nonce"])
    }

    func test_everyRetry_publishesANewNonce_forTheSameCodeMessage() async throws {
        let realtime = RecordingRealtimeClient()
        let item = ChatOutboxItem.sendMessage(dto("retried"))

        try await ChatOutboxRepublisher.republish(item, realtime: realtime)
        try await ChatOutboxRepublisher.republish(item, realtime: realtime)

        let bodies = try realtime.publishedBodies.map(json)
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies.map { $0["codeMessage"] as? String }, ["retried", "retried"])
        let nonces = bodies.map { $0["nonce"] as? String }
        XCTAssertTrue(nonces.allSatisfy(isLowercaseUUID))
        XCTAssertNotEqual(nonces[0], nonces[1], "a retry is a new attempt: new nonce")
    }
}
