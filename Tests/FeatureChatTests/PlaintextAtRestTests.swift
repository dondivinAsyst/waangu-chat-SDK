//
//  PlaintextAtRestTests.swift
//  FeatureChatTests
//
//  CHAT-FE-SDK-W360-B13, F-13 — le texte d'un message n'est plus copié en clair
//  (`searchText`) et l'aperçu de conversation (`lastMessageText`) est chiffré.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class PlaintextAtRestTests: XCTestCase {

    private func makeStore() async -> any SearchableDatabaseProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }

    func test_toModel_keepsNoPlaintextCopy_andEncryptsTheContent() {
        let item = MessageDataItem(
            codeMessage: "m-\(UUID().uuidString)", senderId: "me", groupId: "", typeMessage: .TEXT,
            message: WaanguFeatureChat.MessageContent(text: "secret"), status: .PENDING, createdAt: Date())

        let model = MessageModelMapper.toModel(from: item, conversationId: "c", fieldCrypto: TagCrypto())

        XCTAssertNil(model.searchText)
        XCTAssertNotEqual(model.content.text, "secret")
        XCTAssertEqual(model.content.text.map { TagCrypto().decrypt($0) }, "secret")
    }

    /// Supprimer le dernier message recalcule l'aperçu à partir du précédent : il est stocké
    /// chiffré et se relit en clair par la même clé.
    func test_conversationPreview_isStoredEncrypted() async throws {
        let store = await makeStore()
        let crypto = TagCrypto()
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        try await store.save(conversation)
        let kept = MessageModel(conversationId: conversation.id, senderId: "peer", senderName: "Peer",
                                content: .text(crypto.encrypt("visible \(UUID().uuidString)")),
                                timestamp: Date(timeIntervalSinceNow: -60), deliveryStatus: .delivered)
        let doomed = MessageModel(conversationId: conversation.id, senderId: "peer", senderName: "Peer",
                                  content: .text(crypto.encrypt("gone")), timestamp: Date(),
                                  deliveryStatus: .delivered)
        try await store.save(kept)
        try await store.save(doomed)
        let source = GRDBMessageDataSource(store: store, fieldEncryptionService: crypto)

        try await source.deleteMessage(messageId: doomed.id, forEveryone: false)

        let row = try await store.fetchOne(ConversationModel.self, id: conversation.id)
        let stored = try XCTUnwrap(row?.lastMessageText)
        XCTAssertTrue(stored.hasPrefix("enc:"), "The preview must not be stored in clear")
        XCTAssertEqual(crypto.decrypt(stored), kept.content.text.map { crypto.decrypt($0) })
    }

    /// Un message entrant crée la conversation : aperçu et nom de l'expéditeur y sont chiffrés.
    func test_inboundMessage_storesPreviewAndSenderNameEncrypted() async throws {
        let store = await makeStore()
        let crypto = TagCrypto()
        let delegate = ChatSyncDelegate(fieldCrypto: crypto, currentUserId: { "me" })
        let serverConversationId = "srv-\(UUID().uuidString)"
        let dto = InboundMessageDTO(
            senderId: "peer-\(UUID().uuidString)", senderName: "Alice Martin", senderPhone: "0987",
            senderAvatar: "", receiverId: "me", conversationId: serverConversationId,
            codeMessage: "m-\(UUID().uuidString)", content: "bonjour secret", typeMessage: "TEXT",
            status: "SENT", forwarded: false, viewOnce: false, isMoney: false, isMessageSystem: false)
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dto))
        let eventData = try JSONSerialization.data(withJSONObject: [
            "type": "message", "conversationId": serverConversationId,
            "payload": payload, "at": Date().timeIntervalSince1970,
        ] as [String: Any])
        let event = try JSONDecoder().decode(ChatSyncEventDTO.self, from: eventData)

        await delegate.processEvent(event, database: store)

        let rows = try await store.fetch(
            ConversationModel.self,
            query: QuerySpec(filter: FilterSpec("server_id == %@", .string(serverConversationId)), limit: 1))
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.lastMessageText.map { crypto.decrypt($0) }, "bonjour secret")
        XCTAssertTrue(row.lastMessageText?.hasPrefix("enc:") == true, "Preview must not be stored in clear")
        XCTAssertEqual(row.lastMessageSenderName.map { crypto.decrypt($0) }, "Alice Martin")
        XCTAssertTrue(row.lastMessageSenderName?.hasPrefix("enc:") == true, "Sender name must not be stored in clear")
    }

    func test_readingALegacyPlaintextPreview_stillWorks() {
        XCTAssertEqual(TagCrypto().decrypt("bonjour"), "bonjour")
    }
}

private struct TagCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { "enc:" + String(value.reversed()) }
    func decrypt(_ value: String) -> String {
        value.hasPrefix("enc:") ? String(value.dropFirst(4).reversed()) : value
    }
    func encryptOptional(_ value: String?) -> String? { value.map(encrypt) }
    func decryptOptional(_ value: String?) -> String? { value.map(decrypt) }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
