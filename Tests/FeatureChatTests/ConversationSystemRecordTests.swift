//
//  ConversationSystemRecordTests.swift
//  FeatureChatTests
//
//  "CONVERSATION_CREATED" showed as a text bubble and as the chat list's last
//  message: only the history sync knew conversation system records were not
//  messages. These check the realtime path, the preview rule, and rows already
//  stored the old way. Unit level — says nothing about what the backend sends.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class ConversationSystemRecordTests: XCTestCase {

    private let me = "me"

    // MARK: - Fixtures

    private func makeStore() async -> any SearchableDatabaseProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }

    private func delegate() -> ChatSyncDelegate {
        ChatSyncDelegate(fieldCrypto: PassthroughCrypto(), currentUserId: { [me] in me })
    }

    private func seedConversation(in store: any DatabaseRepositoryProtocol) async throws -> String {
        let id = "conv-\(UUID().uuidString)"
        try await store.save(ConversationModel(id: id, type: .direct))
        return id
    }

    private func dto(conversation: String, code: String, content: String,
                     type: String = "SYSTEM", isSystem: Bool = true) -> InboundMessageDTO {
        InboundMessageDTO(
            senderId: "peer-\(UUID().uuidString)", senderName: "Alice", senderPhone: "0987", senderAvatar: "",
            receiverId: me, conversationId: conversation, codeMessage: code, content: content,
            typeMessage: type, status: "SENT", forwarded: false, viewOnce: false,
            isMoney: false, isMessageSystem: isSystem)
    }

    private func event(_ dto: InboundMessageDTO, conversation: String) throws -> ChatSyncEventDTO {
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as! [String: Any]
        let object: [String: Any] = [
            "type": "message", "payload": payload,
            "at": Date().timeIntervalSince1970, "conversationId": conversation
        ]
        return try JSONDecoder().decode(ChatSyncEventDTO.self,
                                        from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: - Realtime

    func test_conversationCreated_isNotStoredAsAMessage() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let code = "m-\(UUID().uuidString)"

        await delegate().processEvent(
            try event(dto(conversation: conversation, code: code, content: "CONVERSATION_CREATED"),
                      conversation: conversation),
            database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: code)
        XCTAssertNil(stored, "Stored as a message, it read 'CONVERSATION_CREATED' in the thread")
        let checkpoint = try await store.fetchOne(ChatActionModel.self, id: code)
        XCTAssertNil(checkpoint, "Housekeeping: nothing to show")
    }

    func test_contactBlocked_becomesACheckpoint_notAMessage() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let code = "m-\(UUID().uuidString)"

        await delegate().processEvent(
            try event(dto(conversation: conversation, code: code, content: "CONTACT_BLOCKED"),
                      conversation: conversation),
            database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: code)
        XCTAssertNil(stored)
        let checkpoint = try await store.fetchOne(ChatActionModel.self, id: code)
        XCTAssertNotNil(checkpoint)
    }

    func test_ordinaryText_isStillAMessage() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let code = "m-\(UUID().uuidString)"

        // A person typing the words is a message, however they read.
        await delegate().processEvent(
            try event(dto(conversation: conversation, code: code, content: "CONVERSATION_CREATED",
                          type: "TEXT", isSystem: false),
                      conversation: conversation),
            database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: code)
        XCTAssertNotNil(stored)
    }

    // MARK: - Classification

    func test_callRecord_isNotAConversationRecord() {
        // Call records carry isMessageSystem too, and keep their own bubble.
        let call = dto(conversation: "c", code: "x", content: "", type: "CALL_AUDIO", isSystem: true)
        XCTAssertNil(ConversationSystemRecord.kind(of: call))
    }

    func test_kindsReadFromTheContent() {
        XCTAssertEqual(ConversationSystemRecord.kind(content: "CONVERSATION_CREATED"), .conversationCreated)
        XCTAssertEqual(ConversationSystemRecord.kind(content: "CONTACT_UNBLOCKED"), .action(.contactUnblocked))
        XCTAssertEqual(ConversationSystemRecord.kind(content: "CONTACT_BLOCKED"), .action(.contactBlocked))
        XCTAssertEqual(ConversationSystemRecord.kind(content: "MESSAGES_CLEARED"), .action(.messagesCleared))
        XCTAssertEqual(ConversationSystemRecord.kind(content: "SOMETHING_NEW"), .unknown)
    }

    func test_systemRecord_doesNotSpeakForTheConversation() {
        let record = dto(conversation: "c", code: "x", content: "CONVERSATION_CREATED")
        XCTAssertFalse(ConversationPreviewPolicy.updatesPreview(record))

        let text = dto(conversation: "c", code: "y", content: "hello", type: "TEXT", isSystem: false)
        XCTAssertTrue(ConversationPreviewPolicy.updatesPreview(text))
    }

    // MARK: - Rows stored before

    func test_storedSystemRecord_isHiddenFromTheTimeline() {
        let stale = MessageModel(conversationId: "c", senderId: "s", senderName: "S",
                                 type: .system, content: .text("CONVERSATION_CREATED"))
        XCTAssertFalse(MessageTimelineVisibility.isVisible(stale))

        var call = MessageModel(conversationId: "c", senderId: "s", senderName: "S",
                                type: .system, content: .text(""))
        call.content.callIsVideo = false
        call.content.callConnected = true
        XCTAssertTrue(MessageTimelineVisibility.isVisible(call), "A call record must stay")

        let text = MessageModel(conversationId: "c", senderId: "s", senderName: "S",
                                type: .text, content: .text("CONVERSATION_CREATED"))
        XCTAssertTrue(MessageTimelineVisibility.isVisible(text))
    }
}

private struct PassthroughCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
