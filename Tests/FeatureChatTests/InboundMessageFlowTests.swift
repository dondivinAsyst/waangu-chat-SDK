//
//  InboundMessageFlowTests.swift
//  FeatureChatTests
//
//  CHAT-FE-SDK-W360-B13, messaging — what the sync delegate does with the events that
//  carry messages, edits and reactions, on a real database: one row per message however
//  often it is delivered, a delivery state that only moves forward (a failed send recovers
//  when the server confirms it), content that is stored encrypted, one reaction per person.
//  Unit level, against the iOS code: says nothing about what the backend sends.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class InboundMessageFlowTests: XCTestCase {

    private let me = "me"

    // MARK: - Fixtures

    private func makeStore() async -> any SearchableDatabaseProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }

    private func delegate() -> ChatSyncDelegate {
        ChatSyncDelegate(fieldCrypto: FlowCrypto(), currentUserId: { [me] in me })
    }

    /// A conversation keyed by the id the server will name, so the delegate finds it by primary key.
    private func seedConversation(in store: any DatabaseRepositoryProtocol) async throws -> String {
        let id = "conv-\(UUID().uuidString)"
        try await store.save(ConversationModel(id: id, type: .direct))
        return id
    }

    private func seedMessage(
        in store: any DatabaseRepositoryProtocol, conversation: String, sender: String,
        text: String = "hello", status: MessageDeliveryStatusModel
    ) async throws -> MessageModel {
        let message = MessageModel(conversationId: conversation, senderId: sender, senderName: "Someone",
                                   content: .text(FlowCrypto().encrypt(text)), timestamp: Date(),
                                   deliveryStatus: status)
        try await store.save(message)
        return message
    }

    private func event(_ type: String, conversation: String? = nil, reference: String? = nil,
                       payload: [String: Any]) throws -> ChatSyncEventDTO {
        var object: [String: Any] = ["type": type, "payload": payload, "at": Date().timeIntervalSince1970]
        if let conversation { object["conversationId"] = conversation }
        if let reference { object["referenceId"] = reference }
        return try JSONDecoder().decode(ChatSyncEventDTO.self,
                                        from: JSONSerialization.data(withJSONObject: object))
    }

    private func inboundMessage(conversation: String, code: String, sender: String,
                                text: String = "bonjour", status: String = "SENT") throws -> ChatSyncEventDTO {
        let dto = InboundMessageDTO(
            senderId: sender, senderName: "Alice", senderPhone: "0987", senderAvatar: "",
            receiverId: me, conversationId: conversation, codeMessage: code, content: text,
            typeMessage: "TEXT", status: status, forwarded: false, viewOnce: false,
            isMoney: false, isMessageSystem: false)
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as! [String: Any]
        return try event("message", conversation: conversation, payload: payload)
    }

    private func messages(in conversation: String, store: any DatabaseRepositoryProtocol) async throws -> [MessageModel] {
        try await store.fetch(MessageModel.self, query: QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversation))))
    }

    private func reactions(of messageId: String, store: any DatabaseRepositoryProtocol) async throws -> [MessageReactionModel] {
        try await store.fetch(MessageReactionModel.self, query: QuerySpec(
            filter: FilterSpec("message_id == %@", .string(messageId))))
    }

    // MARK: - Messages

    func test_inboundText_isStored_withContentThatDecrypts() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let code = "m-\(UUID().uuidString)"

        await delegate().processEvent(try inboundMessage(conversation: conversation, code: code, sender: "peer-a"),
                                      database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: code)
        let message = try XCTUnwrap(stored)
        XCTAssertEqual(message.senderId, "peer-a")
        XCTAssertNotEqual(message.content.text, "bonjour", "The text must not be stored in clear")
        XCTAssertEqual(message.content.text.map { FlowCrypto().decrypt($0) }, "bonjour")
        XCTAssertNil(message.searchText)
    }

    func test_sameMessageDeliveredTwice_leavesOneRow_andKeepsItsCreationTime() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let code = "m-\(UUID().uuidString)"
        let event = try inboundMessage(conversation: conversation, code: code, sender: "peer-a")

        await delegate().processEvent(event, database: store)
        let first = try await store.fetchOne(MessageModel.self, id: code)
        await delegate().processEvent(event, database: store)

        let rows = try await messages(in: conversation, store: store)
        XCTAssertEqual(rows.filter { $0.id == code }.count, 1, "A redelivery must not add a second row")
        let again = try await store.fetchOne(MessageModel.self, id: code)
        XCTAssertEqual(again?.createdAt, first?.createdAt)
    }

    func test_redelivery_neverLowersAStatusAlreadyReached() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let seeded = try await seedMessage(in: store, conversation: conversation, sender: "peer-a", status: .read)

        await delegate().processEvent(
            try inboundMessage(conversation: conversation, code: seeded.id, sender: "peer-a", status: "SENT"),
            database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: seeded.id)
        XCTAssertEqual(stored?.deliveryStatus, .read)
    }

    func test_ownMessageEcho_neverLowersADeliveredStatus() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let seeded = try await seedMessage(in: store, conversation: conversation, sender: me, status: .delivered)

        await delegate().processEvent(
            try inboundMessage(conversation: conversation, code: seeded.id, sender: me, status: "SENT"),
            database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: seeded.id)
        XCTAssertEqual(stored?.deliveryStatus, .delivered)
    }

    /// A send that failed on this device and was in fact accepted: the server's echo settles it.
    func test_serverEcho_recoversAMessageMarkedFailedLocally() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let seeded = try await seedMessage(in: store, conversation: conversation, sender: me, status: .failed)

        await delegate().processEvent(
            try inboundMessage(conversation: conversation, code: seeded.id, sender: me, status: "SENT"),
            database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: seeded.id)
        XCTAssertEqual(stored?.deliveryStatus, .sent)
    }

    // MARK: - Edits

    func test_edit_replacesTheContent_andMarksTheMessageEdited() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let seeded = try await seedMessage(in: store, conversation: conversation, sender: "peer-a",
                                           text: "old", status: .delivered)

        await delegate().processEvent(try event("message_edited", conversation: conversation, payload: [
            "codeMessage": seeded.id, "conversationId": conversation, "senderId": "peer-a",
            "content": "new text", "modificationTimestamp": Date().timeIntervalSince1970,
        ]), database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: seeded.id)
        let message = try XCTUnwrap(stored)
        XCTAssertEqual(message.content.text.map { FlowCrypto().decrypt($0) }, "new text")
        XCTAssertTrue(message.isEdited)
        XCTAssertNotNil(message.editedAt)
        XCTAssertNil(message.searchText)
    }

    func test_edit_ofAMessageWeDoNotHave_createsNothing() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let unknown = "m-\(UUID().uuidString)"

        await delegate().processEvent(try event("message_edited", conversation: conversation, payload: [
            "codeMessage": unknown, "conversationId": conversation, "senderId": "peer-a", "content": "x",
        ]), database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: unknown)
        XCTAssertNil(stored)
    }

    // MARK: - Reactions

    private func reaction(_ type: String, message: String, conversation: String, user: String,
                          emoji: String) throws -> ChatSyncEventDTO {
        try event(type, conversation: conversation, reference: message, payload: [
            "userId": user, "conversationId": conversation, "codeMessage": message, "reaction": emoji,
        ])
    }

    func test_reaction_isStored_andANewOneFromTheSamePersonReplacesIt() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let seeded = try await seedMessage(in: store, conversation: conversation, sender: me, status: .delivered)

        await delegate().processEvent(try reaction("reaction", message: seeded.id, conversation: conversation,
                                                   user: "peer-a", emoji: "👍"), database: store)
        await delegate().processEvent(try reaction("reaction", message: seeded.id, conversation: conversation,
                                                   user: "peer-a", emoji: "❤️"), database: store)
        await delegate().processEvent(try reaction("reaction", message: seeded.id, conversation: conversation,
                                                   user: "peer-b", emoji: "👍"), database: store)

        let rows = try await reactions(of: seeded.id, store: store)
        XCTAssertEqual(rows.count, 2, "One reaction per person")
        XCTAssertEqual(rows.first { $0.userId == "peer-a" }?.emoji, "❤️")
        XCTAssertEqual(rows.first { $0.userId == "peer-b" }?.emoji, "👍")
    }

    func test_reactionRemoval_deletesOnlyThatPersonsReaction() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let seeded = try await seedMessage(in: store, conversation: conversation, sender: me, status: .delivered)
        for user in ["peer-a", "peer-b"] {
            await delegate().processEvent(try reaction("reaction", message: seeded.id, conversation: conversation,
                                                       user: user, emoji: "👍"), database: store)
        }

        await delegate().processEvent(try reaction("reaction_removed", message: seeded.id, conversation: conversation,
                                                   user: "peer-a", emoji: "👍"), database: store)

        let rows = try await reactions(of: seeded.id, store: store)
        XCTAssertEqual(rows.map(\.userId), ["peer-b"])
    }

    /// KNOWN GAP. `InboundReactMessageDTO.isRemoval` says an empty reaction removes it, but
    /// `BackendMessageReactionEventDTO` has only optional fields, so every payload decodes as
    /// that type first and the simplified one is never consulted: the event is dropped
    /// ("ADDED ignored — empty emoji") and the reaction stays. Whether the server ever signals a
    /// removal this way is the open question; `reaction_removed` works (test above).
    func test_knownGap_reactionWithAnEmptyEmoji_shouldRemoveIt() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let seeded = try await seedMessage(in: store, conversation: conversation, sender: me, status: .delivered)
        await delegate().processEvent(try reaction("reaction", message: seeded.id, conversation: conversation,
                                                   user: "peer-a", emoji: "👍"), database: store)

        await delegate().processEvent(try reaction("reaction", message: seeded.id, conversation: conversation,
                                                   user: "peer-a", emoji: ""), database: store)

        let rows = try await reactions(of: seeded.id, store: store)
        XCTExpectFailure("Empty-emoji removal is dead code behind the all-optional backend DTO")
        XCTAssertTrue(rows.isEmpty)
    }

    func test_reaction_onAMessageWeDoNotHave_isIgnored() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let unknown = "m-\(UUID().uuidString)"

        await delegate().processEvent(try reaction("reaction", message: unknown, conversation: conversation,
                                                   user: "peer-a", emoji: "👍"), database: store)

        let rows = try await reactions(of: unknown, store: store)
        XCTAssertTrue(rows.isEmpty)
    }
}

private struct FlowCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { "enc:" + String(value.reversed()) }
    func decrypt(_ value: String) -> String {
        value.hasPrefix("enc:") ? String(value.dropFirst(4).reversed()) : value
    }
    func encryptOptional(_ value: String?) -> String? { value.map(encrypt) }
    func decryptOptional(_ value: String?) -> String? { value.map(decrypt) }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
