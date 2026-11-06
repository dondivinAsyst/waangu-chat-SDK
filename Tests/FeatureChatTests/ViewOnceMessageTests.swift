//
//  ViewOnceMessageTests.swift
//  FeatureChatTests
//
//  A view-once message is opened once on each device, then only an "Opened"
//  line is left. The flag has to survive every hop on the way out and in, and
//  an opened copy must stay opened — the server still holds the original, so
//  any echo of it is a chance to bring the content back.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class ViewOnceMessageTests: XCTestCase {

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

    private func inboundVoice(conversation: String, code: String, viewOnce: Bool) throws -> ChatSyncEventDTO {
        let dto = InboundMessageDTO(
            senderId: "peer-\(UUID().uuidString)", senderName: "Alice", senderPhone: "0987", senderAvatar: "",
            receiverId: me, conversationId: conversation, codeMessage: code,
            content: "{\"url\":\"https://cdn.invalid/v.opus\",\"fileName\":\"v.opus\"}",
            typeMessage: "VOICE", status: "SENT", forwarded: false, viewOnce: viewOnce,
            isMoney: false, isMessageSystem: false)
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as! [String: Any]
        let object: [String: Any] = [
            "type": "message", "payload": payload,
            "at": Date().timeIntervalSince1970, "conversationId": conversation
        ]
        return try JSONDecoder().decode(ChatSyncEventDTO.self,
                                        from: JSONSerialization.data(withJSONObject: object))
    }

    private func voiceItem(viewOnce: Bool, openedAt: Date? = nil) -> MessageDataItem {
        var content = MessageContent()
        content.audio = "https://cdn.invalid/v.opus"
        content.fileName = "v.opus"
        content.viewOnceOpenedAt = openedAt
        var item = OutgoingMessageBuilder.buildOutgoingMessage(
            content: content, type: .VOICE, groupId: nil, reply: nil, viewOnce: viewOnce)
        item.message.viewOnceOpenedAt = openedAt
        return item
    }

    // MARK: - Out

    func test_outgoingVoice_carriesViewOnce_toTheWire() {
        let item = voiceItem(viewOnce: true)
        XCTAssertTrue(item.isViewOnce)

        let dto = OutboundMessageDTOBuilder.build(from: item, conversationId: "c", recipientId: "peer")
        XCTAssertEqual(dto.viewOnce, true)
    }

    func test_ordinaryVoice_isNotViewOnce() {
        XCTAssertFalse(voiceItem(viewOnce: false).isViewOnce)
    }

    // MARK: - In

    func test_inboundViewOnce_isStored() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let code = "m-\(UUID().uuidString)"

        await delegate().processEvent(try inboundVoice(conversation: conversation, code: code, viewOnce: true),
                                      database: store)

        let stored = try await store.fetchOne(MessageModel.self, id: code)
        XCTAssertEqual(try XCTUnwrap(stored).isViewOnce, true,
                       "The flag was dropped by the inbound mapper, so the message arrived as an ordinary one")
    }

    // MARK: - Opened stays opened

    func test_openedAt_survivesStorage_andNeverGoesOnTheWire() throws {
        let openedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let item = voiceItem(viewOnce: true, openedAt: openedAt)

        let model = MessageModelMapper.toModel(from: item, conversationId: "c", fieldCrypto: PassthroughCrypto())
        XCTAssertEqual(model.content.viewOnceOpenedAt, openedAt)
        XCTAssertTrue(model.isViewOnce)

        let back = MessageModelMapper.toDomain(model, fieldCrypto: PassthroughCrypto())
        XCTAssertEqual(back.message.viewOnceOpenedAt, openedAt)
        XCTAssertTrue(back.isViewOnceOpened)

        let wire = try JSONEncoder().encode(OutboundMessageDTOBuilder.build(from: item, conversationId: "c", recipientId: nil))
        XCTAssertFalse(String(decoding: wire, as: UTF8.self).contains("viewOnceOpenedAt"),
                       "Each side opens its own copy; the date is this device's business")
    }

    func test_serverEcho_doesNotReviveAnOpenedMessage() async throws {
        let store = await makeStore()
        let conversation = try await seedConversation(in: store)
        let code = "m-\(UUID().uuidString)"
        let event = try inboundVoice(conversation: conversation, code: code, viewOnce: true)

        await delegate().processEvent(event, database: store)
        let firstStored = try await store.fetchOne(MessageModel.self, id: code)
        var opened = try XCTUnwrap(firstStored)
        opened.content = MessageContentModel(viewOnceOpenedAt: Date())
        try await store.save(opened)

        await delegate().processEvent(event, database: store)

        let echoed = try await store.fetchOne(MessageModel.self, id: code)
        let afterEcho = try XCTUnwrap(echoed)
        XCTAssertNotNil(afterEcho.content.viewOnceOpenedAt)
        XCTAssertNil(afterEcho.content.url, "The echo brought the audio back")
        XCTAssertNil(afterEcho.content.fileName)
        XCTAssertTrue(afterEcho.isViewOnce)
    }

    // MARK: - What is left after opening

    func test_openedMessageWithContent_needsWiping_andAnEmptyOneDoesNot() {
        let openedAt = Date()
        XCTAssertTrue(voiceItem(viewOnce: true, openedAt: openedAt).viewOnceNeedsWipe)

        var wiped = voiceItem(viewOnce: true, openedAt: openedAt)
        wiped.message.audio = nil
        wiped.message.fileName = nil
        XCTAssertFalse(wiped.viewOnceNeedsWipe)
        XCTAssertTrue(wiped.isViewOnceOpened)

        XCTAssertFalse(voiceItem(viewOnce: true).isViewOnceOpened, "Not opened until it is")
    }

    // MARK: - Nothing to pass on

    func test_menu_offersNoForwardOrCopy_forViewOnce() {
        let actions = MessageMenuAction.menuActions(for: voiceItem(viewOnce: true))
        XCTAssertFalse(actions.contains(.forward))
        XCTAssertFalse(actions.contains(.copy))
        XCTAssertTrue(actions.contains(.reply))
        XCTAssertTrue(actions.contains(.delete))

        let ordinary = MessageMenuAction.menuActions(for: voiceItem(viewOnce: false))
        XCTAssertTrue(ordinary.contains(.forward))
    }

    func test_previewNeverShowsTheContent() {
        var item = voiceItem(viewOnce: true)
        item.message.text = "secret"
        XCTAssertEqual(MessageModelMapper.buildLastMessagePreview(item), "⏱ View once message")
        XCTAssertEqual(MessageReplyWireCodec.replyPreview(for: item), "View once message")
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
