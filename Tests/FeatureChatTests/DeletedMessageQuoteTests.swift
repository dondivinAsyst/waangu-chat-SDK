//
//  DeletedMessageQuoteTests.swift
//  FeatureChatTests
//
//  B44, suite — ce qu'un message supprimé pour tous laisse derrière lui.
//  Une réponse garde sa propre copie du texte cité : elle doit la perdre quand
//  l'original est supprimé pour tous, et ne pas la retrouver sur un écho
//  serveur. Les fichiers reçus partent aussi quand l'autre supprime.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class DeletedMessageQuoteTests: XCTestCase {

    private let me = "me"
    private let peer = "peer-1"
    private let serverTime = Date(timeIntervalSince1970: 1_791_000_000)

    // MARK: - Les citations perdent leur copie

    func test_peerDeletesForEveryone_redactsQuotesOfIt() async throws {
        let (store, original, reply) = try await seedOriginalAndReply()

        await send("message_deleted", reference: original, payload: ["forEveryone": true, "deletedBy": peer], in: store)

        let stored = try await fetch(reply, in: store)
        XCTAssertEqual(stored.replyToIsDeleted, true)
        XCTAssertNil(stored.replyToMessagePreview)
        XCTAssertNil(stored.replyToThumbnailURL)
        XCTAssertEqual(stored.replyToMessageId, original.id, "the reply still points at what it answered")
    }

    func test_myDeleteForEveryoneConfirmed_redactsQuotesOfIt() async throws {
        let (store, original, reply) = try await seedOriginalAndReply(originalSender: me, deleted: true)

        await send("delete_ack", reference: original, payload: ["forEveryone": true], in: store)

        let stored = try await fetch(reply, in: store)
        XCTAssertEqual(stored.replyToIsDeleted, true)
        XCTAssertNil(stored.replyToMessagePreview)
    }

    /// Une suppression qui échoue n'a rien supprimé : la citation reste.
    func test_failedDeleteForEveryone_keepsTheQuote() async throws {
        let (store, original, reply) = try await seedOriginalAndReply(originalSender: me, deleted: true)

        await send("delete_failed", reference: original, payload: ["forEveryone": true], in: store)

        let stored = try await fetch(reply, in: store)
        XCTAssertNotEqual(stored.replyToIsDeleted, true)
        XCTAssertEqual(stored.replyToMessagePreview, "texte d'origine")
    }

    /// « Supprimer pour moi » ne retire rien aux autres : la citation reste.
    func test_deleteForMeOnly_keepsTheQuote() async throws {
        let (store, original, reply) = try await seedOriginalAndReply(originalSender: me, deleted: true)

        await send("delete_ack", reference: original, payload: ["forEveryone": false], in: store)

        let stored = try await fetch(reply, in: store)
        XCTAssertNotEqual(stored.replyToIsDeleted, true)
        XCTAssertEqual(stored.replyToMessagePreview, "texte d'origine")
    }

    // MARK: - Réponses arrivées après coup

    /// La réponse arrive après la suppression : elle n'apporte pas le texte supprimé.
    func test_replyArrivingAfterTheDelete_isStoredRedacted() async throws {
        let store = await Self.makeStore()
        let conversation = try await seedConversation(in: store)
        let original = MessageModel(conversationId: conversation.id, senderId: peer, senderName: "Peer",
                                    content: .text("texte d'origine"), timestamp: serverTime,
                                    isDeleted: true, isDeletedForAll: true)
        try await store.save(original)

        let replyId = "reply-\(UUID().uuidString.lowercased())"
        await send("message", referenceId: replyId, conversationId: conversation.id,
                   payload: inboundReply(id: replyId, conversationId: conversation.id, quoting: original.id),
                   in: store)

        let fetched = try await store.fetchOne(MessageModel.self, id: replyId)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.replyToIsDeleted, true)
        XCTAssertNil(stored.replyToMessagePreview)
    }

    /// Le serveur renvoie la réponse avec sa citation d'origine : elle reste vidée.
    func test_serverEchoOfARedactedReply_staysRedacted() async throws {
        let (store, original, reply) = try await seedOriginalAndReply()
        await send("message_deleted", reference: original, payload: ["forEveryone": true, "deletedBy": peer], in: store)

        await send("message", referenceId: reply.id, conversationId: reply.conversationId,
                   payload: inboundReply(id: reply.id, conversationId: reply.conversationId, quoting: original.id),
                   in: store)

        let stored = try await fetch(reply, in: store)
        XCTAssertEqual(stored.replyToIsDeleted, true)
        XCTAssertNil(stored.replyToMessagePreview)
    }

    // MARK: - Écho serveur d'un message supprimé

    /// Supprimé pour moi ici, renvoyé tel quel par le serveur : il reste supprimé.
    func test_realtimeEchoOfAMessageDeletedHere_staysDeleted() async throws {
        let (store, original, _) = try await seedOriginalAndReply(deleted: true)
        let payload = inboundMessage(id: original.id, conversationId: original.conversationId, text: "texte d'origine")

        await send("message", referenceId: original.id, conversationId: original.conversationId, payload: payload, in: store)

        let stored = try await fetch(original, in: store)
        XCTAssertTrue(stored.isDeleted)
        XCTAssertTrue(stored.isDeletedForAll)
        XCTAssertNil(stored.searchText)
    }

    // MARK: - Résumé de boîte de réception

    /// Le résumé renvoie le dernier message de chaque conversation ; il ne doit
    /// ni « dé-supprimer » un message, ni rendre une citation vidée.
    func test_inboxSummary_doesNotUndeleteTheLastMessage() async throws {
        let (store, original, _) = try await seedOriginalAndReply(deleted: true)

        await pullSummary(lastMessage: inboundMessage(id: original.id, conversationId: original.conversationId,
                                                      text: "texte d'origine"),
                          conversationId: original.conversationId, into: store)

        let stored = try await fetch(original, in: store)
        XCTAssertTrue(stored.isDeleted)
        XCTAssertNil(stored.searchText)
    }

    func test_inboxSummary_keepsARedactedQuoteRedacted() async throws {
        let (store, original, reply) = try await seedOriginalAndReply()
        await send("message_deleted", reference: original, payload: ["forEveryone": true, "deletedBy": peer], in: store)

        await pullSummary(lastMessage: inboundReply(id: reply.id, conversationId: reply.conversationId, quoting: original.id),
                          conversationId: reply.conversationId, into: store)

        let stored = try await fetch(reply, in: store)
        XCTAssertEqual(stored.replyToIsDeleted, true)
        XCTAssertNil(stored.replyToMessagePreview)
    }

    /// Un dernier message inconnu de l'appareil est enregistré normalement.
    func test_inboxSummary_storesAnUnknownLastMessage() async throws {
        let store = await Self.makeStore()
        let conversation = try await seedConversation(in: store)
        let id = "m-\(UUID().uuidString.lowercased())"

        await pullSummary(lastMessage: inboundMessage(id: id, conversationId: conversation.id, text: "bonjour"),
                          conversationId: conversation.id, into: store)

        let fetched = try await store.fetchOne(MessageModel.self, id: id)
        let stored = try XCTUnwrap(fetched)
        XCTAssertFalse(stored.isDeleted)
        XCTAssertEqual(stored.content.text, "bonjour")
    }

    // MARK: - Lecture

    func test_redactedQuote_reachesTheViewAsDeleted_withoutText() {
        let model = MessageModel(conversationId: "c", senderId: peer, senderName: "Peer",
                                 content: .text("ma réponse"),
                                 replyToMessageId: "orig", replyToSenderName: "Aline",
                                 replyToMessageType: .image, replyToIsDeleted: true)

        let item = MessageModelMapper.toDomain(model, fieldCrypto: PassthroughFieldCrypto())

        guard case .message(let quoted?) = item.reply else { return XCTFail("reply expected") }
        XCTAssertTrue(quoted.isDeleted)
        XCTAssertEqual(quoted.message.text, "")
        XCTAssertNil(quoted.message.thumbnail)
        XCTAssertEqual(quoted.typeMessage, .TEXT, "no media placeholder for a deleted quote")
        XCTAssertEqual(quoted.senderName, "Aline")
    }

    /// Une ligne écrite avant ce champ se relit : `nil` vaut « non supprimé ».
    func test_rowWrittenBeforeTheField_stillDecodes() throws {
        let model = MessageModel(conversationId: "c", senderId: peer, senderName: "Peer",
                                 replyToMessageId: "orig", replyToMessagePreview: "texte")
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(model)) as? [String: Any])
        json.removeValue(forKey: "replyToIsDeleted")

        let decoded = try JSONDecoder().decode(MessageModel.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertNil(decoded.replyToIsDeleted)
        XCTAssertEqual(decoded.replyToMessagePreview, "texte")
    }

    // MARK: - Contenu du message supprimé

    func test_peerDeletesForEveryone_wipesTheContent_keepsBatchAndType() async throws {
        let (store, message) = try await seedRichMessage(sender: peer)

        await send("message_deleted", reference: message, payload: ["forEveryone": true, "deletedBy": peer], in: store)

        let stored = try await fetch(message, in: store)
        XCTAssertNil(stored.content.text)
        XCTAssertNil(stored.content.url)
        XCTAssertNil(stored.content.fileName)
        XCTAssertNil(stored.content.latitude)
        XCTAssertEqual(stored.content.mediaBatchId, "batch-1", "bubbles of a multi-send stay grouped")
        XCTAssertEqual(stored.type, .image)
    }

    func test_myDeleteForEveryoneConfirmed_wipesTheContent() async throws {
        let (store, message) = try await seedRichMessage(sender: me, deleted: true)

        await send("delete_ack", reference: message, payload: ["forEveryone": true], in: store)

        let stored = try await fetch(message, in: store)
        XCTAssertNil(stored.content.text)
        XCTAssertNil(stored.content.url)
    }

    /// Rien n'est vidé avant la confirmation du serveur.
    func test_failedDeleteForEveryone_keepsTheContent() async throws {
        let (store, message) = try await seedRichMessage(sender: me, deleted: true)

        await send("delete_failed", reference: message, payload: ["forEveryone": true], in: store)

        let stored = try await fetch(message, in: store)
        XCTAssertEqual(stored.content.text, "légende privée")
    }

    func test_deleteForMeOnly_keepsTheContent() async throws {
        let (store, message) = try await seedRichMessage(sender: me, deleted: true)

        await send("delete_ack", reference: message, payload: ["forEveryone": false], in: store)

        let stored = try await fetch(message, in: store)
        XCTAssertEqual(stored.content.text, "légende privée")
    }

    /// Les références financières appartiennent au serveur : elles restent.
    func test_wipe_keepsFinancialReferences() {
        var content = MessageContentModel(text: "merci pour le repas")
        content.paymentRef = "pay-1"
        content.paymentAmountDecimal = "12.50"
        content.financialObjectType = "MONEY_REQUEST"
        content.financialCorrelationId = "corr-1"

        let kept = ChatSyncDelegate.redactedContent(of: content)

        XCTAssertNil(kept.text)
        XCTAssertEqual(kept.paymentRef, "pay-1")
        XCTAssertEqual(kept.paymentAmountDecimal, "12.50")
        XCTAssertEqual(kept.financialObjectType, "MONEY_REQUEST")
        XCTAssertEqual(kept.financialCorrelationId, "corr-1")
    }

    /// Le serveur renvoie le message avec son contenu d'origine : il reste vidé.
    func test_serverEchoAfterTheWipe_doesNotRestoreTheContent() async throws {
        let (store, message) = try await seedRichMessage(sender: peer)
        await send("message_deleted", reference: message, payload: ["forEveryone": true, "deletedBy": peer], in: store)

        await send("message", referenceId: message.id, conversationId: message.conversationId,
                   payload: inboundMessage(id: message.id, conversationId: message.conversationId, text: "légende privée"),
                   in: store)

        let stored = try await fetch(message, in: store)
        XCTAssertNil(stored.content.text)
        XCTAssertTrue(stored.isDeletedForAll)
    }

    // MARK: - Fichiers reçus

    func test_peerDeletesForEveryone_removesTheReceivedImage() async throws {
        let store = await Self.makeStore()
        let conversation = try await seedConversation(in: store)
        let image = MessageModel(conversationId: conversation.id, senderId: peer, senderName: "Peer",
                                 type: .image, timestamp: serverTime)
        try await store.save(image)
        DiskMediaManager.shared.saveImageDataToDisk(Data([0xFF, 0xD8, 0xFF, 0xD9]), fileName: image.id, pathName: .CHAT)
        XCTAssertTrue(DiskMediaManager.shared.hasDiskImage(for: image.id, pathName: .CHAT))

        await send("message_deleted", reference: image, payload: ["forEveryone": true, "deletedBy": peer], in: store)

        XCTAssertFalse(DiskMediaManager.shared.hasDiskImage(for: image.id, pathName: .CHAT))
    }

    /// Le fichier se retrouve par le nom porté par le contenu : il doit partir
    /// même si le contenu est vidé par la même suppression.
    func test_peerDeletesAVoiceNote_removesTheAudioFile() async throws {
        let store = await Self.makeStore()
        let conversation = try await seedConversation(in: store)
        let voice = MessageModel(conversationId: conversation.id, senderId: peer, senderName: "Peer", type: .voice,
                                 content: MessageContentModel(fileName: "note.opus"), timestamp: serverTime)
        try await store.save(voice)
        DiskMediaManager.shared.saveAudioDataToDisk(data: Data("OggS".utf8), fileName: voice.id, ext: "opus", pathName: .CHAT)
        XCTAssertTrue(DiskMediaManager.shared.hasDiskAudio(for: voice.id, ext: "opus", pathName: .CHAT))

        await send("message_deleted", reference: voice, payload: ["forEveryone": true, "deletedBy": peer], in: store)

        XCTAssertFalse(DiskMediaManager.shared.hasDiskAudio(for: voice.id, ext: "opus", pathName: .CHAT))
    }

    /// L'audio est écrit sous CHAT/<id>.<ext> ; la suppression cherchait sous CHAT/files/.
    func test_mediaCleanup_removesVoiceNotes() {
        let id = "voice-\(UUID().uuidString.lowercased())"
        DiskMediaManager.shared.saveAudioDataToDisk(data: Data("OggS".utf8), fileName: id, ext: "opus", pathName: .CHAT)
        var content = WaanguFeatureChat.MessageContent()
        content.fileName = "note.opus"

        ChatRoomMessageMediaCleanup.deleteMediaFiles(
            for: MessageDataItem(codeMessage: id, typeMessage: .VOICE, message: content, createdAt: serverTime)
        )

        XCTAssertFalse(DiskMediaManager.shared.hasDiskAudio(for: id, ext: "opus", pathName: .CHAT))
    }

    /// Les images sont écrites en .jpg ; la suppression ne visait que .png.
    func test_mediaCleanup_removesJPEGImages() {
        let id = "img-\(UUID().uuidString.lowercased())"
        DiskMediaManager.shared.saveImageDataToDisk(Data([0xFF, 0xD8, 0xFF, 0xD9]), fileName: id, pathName: .CHAT)
        XCTAssertTrue(DiskMediaManager.shared.hasDiskImage(for: id, pathName: .CHAT))

        ChatRoomMessageMediaCleanup.deleteMediaFiles(
            for: MessageDataItem(codeMessage: id, typeMessage: .IMAGE, message: MessageContent(), createdAt: serverTime)
        )

        XCTAssertFalse(DiskMediaManager.shared.hasDiskImage(for: id, pathName: .CHAT))
    }

    // MARK: - Outils

    private func seedConversation(in store: any DatabaseRepositoryProtocol) async throws -> ConversationModel {
        // Un message n'existe qu'avec sa conversation (clé étrangère).
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        try await store.save(conversation)
        return conversation
    }

    private func seedRichMessage(
        sender: String,
        deleted: Bool = false
    ) async throws -> (any DatabaseRepositoryProtocol, MessageModel) {
        let store = await Self.makeStore()
        let conversation = try await seedConversation(in: store)
        var content = MessageContentModel(text: "légende privée", url: "https://cdn.invalid/p.jpg", fileName: "p.jpg")
        content.latitude = -3.38
        content.mediaBatchId = "batch-1"
        let message = MessageModel(conversationId: conversation.id, senderId: sender, senderName: "S", type: .image,
                                   content: content, timestamp: serverTime, deliveryStatus: .pending,
                                   isDeleted: deleted, isDeletedForAll: deleted)
        try await store.save(message)
        return (store, message)
    }

    private func seedOriginalAndReply(
        originalSender: String? = nil,
        deleted: Bool = false
    ) async throws -> (any DatabaseRepositoryProtocol, MessageModel, MessageModel) {
        let store = await Self.makeStore()
        let conversation = try await seedConversation(in: store)
        let original = MessageModel(conversationId: conversation.id, senderId: originalSender ?? peer, senderName: "Peer",
                                    content: .text("texte d'origine"), timestamp: serverTime,
                                    deliveryStatus: .pending, isDeleted: deleted, isDeletedForAll: deleted)
        let reply = MessageModel(conversationId: conversation.id, senderId: me, senderName: "Me",
                                 content: .text("ma réponse"), timestamp: serverTime.addingTimeInterval(1),
                                 deliveryStatus: .sent,
                                 replyToMessageId: original.id, replyToSenderName: "Peer",
                                 replyToMessageType: .text, replyToMessagePreview: "texte d'origine",
                                 replyToThumbnailURL: "https://example.invalid/thumb.jpg")
        try await store.save(original)
        try await store.save(reply)
        return (store, original, reply)
    }

    private func inboundMessage(id: String, conversationId: String, text: String) -> [String: Any] {
        let contentJSON = String(data: try! JSONSerialization.data(withJSONObject: ["text": text]), encoding: .utf8)!
        return ["codeMessage": id, "senderId": peer, "senderName": "Peer", "conversationId": conversationId,
                "content": contentJSON, "typeMessage": "TEXT", "timestamp": serverTime.timeIntervalSince1970]
    }

    private func pullSummary(
        lastMessage: [String: Any],
        conversationId: String,
        into store: any DatabaseRepositoryProtocol
    ) async {
        let summary: [String: Any] = ["id": conversationId, "type": "DIRECT", "participantIds": [me, peer],
                                      "lastMessage": lastMessage, "unreadCount": 0,
                                      "updatedAt": serverTime.timeIntervalSince1970, "status": "ACTIVE"]
        let body = try! JSONSerialization.data(withJSONObject: ["conversations": [summary], "syncTimestamp": 0])
        let me = self.me
        _ = await ChatSyncDelegate(fieldCrypto: PassthroughFieldCrypto(), currentUserId: { me })
            .pullInboxSummary(apiClient: JSONStubClient(body: body), database: store)
    }

    private func inboundReply(id: String, conversationId: String, quoting originalId: String) -> [String: Any] {
        let content: [String: Any] = ["text": "ma réponse", "replyToMessageId": originalId,
                                      "replyToSenderName": "Peer", "replyToMessageType": "TEXT",
                                      "replyToMessagePreview": "texte d'origine"]
        let contentJSON = String(data: try! JSONSerialization.data(withJSONObject: content), encoding: .utf8)!
        return ["codeMessage": id, "senderId": peer, "senderName": "Peer", "conversationId": conversationId,
                "content": contentJSON, "typeMessage": "TEXT", "timestamp": serverTime.timeIntervalSince1970]
    }

    private func send(
        _ type: String,
        reference message: MessageModel,
        payload: [String: Any]? = nil,
        in store: any DatabaseRepositoryProtocol
    ) async {
        await send(type, referenceId: message.id, conversationId: message.conversationId, payload: payload, in: store)
    }

    private func send(
        _ type: String,
        referenceId: String,
        conversationId: String,
        payload: [String: Any]?,
        in store: any DatabaseRepositoryProtocol
    ) async {
        let raw = payload.flatMap { try? JSONSerialization.data(withJSONObject: $0) }.map(AnyCodablePayload.init(rawData:))
        let event = ChatSyncEventDTO(type: type, referenceId: referenceId, conversationId: conversationId,
                                     payload: raw, at: serverTime.timeIntervalSince1970)
        let me = self.me
        await ChatSyncDelegate(fieldCrypto: PassthroughFieldCrypto(), currentUserId: { me })
            .processEvent(event, database: store)
    }

    private func fetch(_ message: MessageModel, in store: any DatabaseRepositoryProtocol) async throws -> MessageModel {
        let fetched = try await store.fetchOne(MessageModel.self, id: message.id)
        return try XCTUnwrap(fetched)
    }

    private static func makeStore() async -> any DatabaseRepositoryProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }
}

/// Rend toujours le même corps JSON, décodé dans le type demandé.
private final class JSONStubClient: APIClientProtocol, @unchecked Sendable {
    private let body: Data
    init(body: Data) { self.body = body }

    var isConnected: Bool { get async { true } }
    func request<T: Decodable>(endpoint: any APIEndpoint) async throws -> T {
        try JSONDecoder().decode(T.self, from: body)
    }
    func cancelRequest(for endpoint: any APIEndpoint) async {}
    func cancelAllRequests() async {}
    func getPerformanceMetrics() async -> APIPerformanceMetrics {
        APIPerformanceMetrics(totalRequests: 0, successCount: 0, failureCount: 0, averageDuration: 0,
                              rateLimitedCount: 0, circuitBreakerBlockCount: 0)
    }
}

private struct PassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
