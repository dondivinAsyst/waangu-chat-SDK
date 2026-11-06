//
//  ReplyWireTests.swift
//  FeatureChatTests
//
//  Harness 360 — matrice miroir : réponse.
//  Une réponse transporte un instantané du message cité (id, auteur, type,
//  aperçu, vignette) dans le JSON `content`. Ce que l'appareil envoie, ce qu'il
//  relit — format courant et ancien `reply` de premier niveau — et ce qui
//  survit au passage par la base.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class ReplyWireTests: XCTestCase {

    private let crypto = PassthroughFieldCrypto()

    // MARK: - Envoi

    func test_outgoingReplyToText_carriesTheQuotedSnapshot() {
        let quoted = item("orig-1", type: .TEXT, text: "  on se voit à 18h  ", sender: "Aline")

        let dto = MessageContentWireCodec.buildContentDTO(from: reply(to: quoted))

        XCTAssertEqual(dto.replyToMessageId, "orig-1")
        XCTAssertEqual(dto.replyToSenderName, "Aline")
        XCTAssertEqual(dto.replyToMessageType, MessageTypeProps.TEXT.rawValue)
        XCTAssertEqual(dto.replyToMessagePreview, "on se voit à 18h", "preview is trimmed")
        XCTAssertNil(dto.replyToThumbnailURL)
    }

    /// Une photo sans légende est citée par son type, avec sa vignette.
    func test_outgoingReplyToCaptionlessPhoto_usesTypeLabelAndThumbnail() {
        var content = WaanguFeatureChat.MessageContent(text: "")
        content.thumbnail = "https://cdn.invalid/t.jpg"
        let quoted = item("orig-2", type: .IMAGE, content: content, sender: "Aline")

        let dto = MessageContentWireCodec.buildContentDTO(from: reply(to: quoted))

        XCTAssertEqual(dto.replyToMessagePreview, "Photo")
        XCTAssertEqual(dto.replyToThumbnailURL, "https://cdn.invalid/t.jpg")
    }

    /// Sans auteur connu, le champ est absent plutôt que vide.
    func test_outgoingReply_withoutSenderName_omitsIt() {
        let dto = MessageContentWireCodec.buildContentDTO(from: reply(to: item("orig-3", type: .TEXT, text: "ok", sender: "")))

        XCTAssertNil(dto.replyToSenderName)
    }

    func test_outgoingMessageWithoutReply_carriesNoReplyFields() {
        let dto = MessageContentWireCodec.buildContentDTO(from: item("m", type: .TEXT, text: "salut", sender: "Me"))

        XCTAssertNil(dto.replyToMessageId)
        XCTAssertNil(dto.replyToMessagePreview)
    }

    // MARK: - Réception

    func test_inboundReplyInContent_reachesTheViewAsAQuote() throws {
        let dto = try inbound(content: ["text": "d'accord", "replyToMessageId": "orig-1", "replyToSenderName": "Aline",
                                        "replyToMessageType": "TEXT", "replyToMessagePreview": "on se voit à 18h"])

        let quoted = try quote(of: dto)

        XCTAssertEqual(quoted.codeMessage, "orig-1")
        XCTAssertEqual(quoted.senderName, "Aline")
        XCTAssertEqual(quoted.typeMessage, .TEXT)
        XCTAssertEqual(quoted.message.text, "on se voit à 18h")
        XCTAssertFalse(quoted.isDeleted)
    }

    /// Ancien format : l'instantané arrive dans un `reply` JSON de premier niveau.
    func test_inboundLegacyTopLevelReply_isStillRead() throws {
        let legacy = String(data: try JSONSerialization.data(withJSONObject: [
            "replyToMessageId": "orig-legacy", "replyToSenderName": "Aline",
            "replyToMessageType": "IMAGE", "replyToMessagePreview": "Photo",
            "replyToThumbnailURL": "https://cdn.invalid/t.jpg"
        ]), encoding: .utf8)!
        let dto = try inbound(content: ["text": "jolie"], extra: ["reply": legacy])

        let quoted = try quote(of: dto)

        XCTAssertEqual(quoted.codeMessage, "orig-legacy")
        XCTAssertEqual(quoted.typeMessage, .IMAGE)
        XCTAssertEqual(quoted.message.thumbnail, "https://cdn.invalid/t.jpg")
    }

    /// Les deux présents : le format courant l'emporte.
    func test_inboundContentReply_winsOverLegacyReply() throws {
        let legacy = String(data: try JSONSerialization.data(withJSONObject: ["replyToMessageId": "old"]), encoding: .utf8)!
        let dto = try inbound(content: ["text": "x", "replyToMessageId": "new"], extra: ["reply": legacy])

        XCTAssertEqual(dto.replyToMessageId, "new")
    }

    func test_inboundMessageWithoutReply_hasNoQuote() throws {
        let dto = try inbound(content: ["text": "salut"])

        let model = try XCTUnwrap(MessageModelMapper.toModel(from: dto, fieldCrypto: crypto))

        XCTAssertNil(MessageModelMapper.toDomain(model, fieldCrypto: crypto).reply)
    }

    // MARK: - Passage par la base

    /// Ma réponse, enregistrée puis relue, cite toujours le même message.
    func test_ownReply_survivesStorageRoundTrip() throws {
        let quoted = item("orig-1", type: .TEXT, text: "on se voit à 18h", sender: "Aline")

        let model = MessageModelMapper.toModel(from: reply(to: quoted), conversationId: "c", fieldCrypto: crypto)
        let back = MessageModelMapper.toDomain(model, fieldCrypto: crypto)

        guard case .message(let roundTripped?) = back.reply else { return XCTFail("reply expected") }
        XCTAssertEqual(roundTripped.codeMessage, "orig-1")
        XCTAssertEqual(roundTripped.senderName, "Aline")
        XCTAssertEqual(roundTripped.message.text, "on se voit à 18h")
    }

    // MARK: - Outils

    private func item(
        _ id: String,
        type: MessageTypeProps,
        text: String = "",
        content: WaanguFeatureChat.MessageContent? = nil,
        sender: String
    ) -> MessageDataItem {
        MessageDataItem(codeMessage: id, senderId: "u-\(sender)", senderName: sender, typeMessage: type,
                        message: content ?? MessageContent(text: text), createdAt: Date(timeIntervalSince1970: 1_791_000_000))
    }

    private func reply(to quoted: MessageDataItem) -> MessageDataItem {
        var message = item("reply-\(UUID().uuidString)", type: .TEXT, text: "ma réponse", sender: "Me")
        message.reply = .message(quoted)
        return message
    }

    private func inbound(content: [String: Any], extra: [String: Any] = [:]) throws -> InboundMessageDTO {
        let contentJSON = String(data: try JSONSerialization.data(withJSONObject: content), encoding: .utf8)!
        var payload: [String: Any] = ["codeMessage": "m-\(UUID().uuidString)", "senderId": "peer", "senderName": "Peer",
                                      "conversationId": "c", "content": contentJSON, "typeMessage": "TEXT",
                                      "timestamp": 1_791_000_000]
        payload.merge(extra) { _, new in new }
        return try JSONDecoder().decode(InboundMessageDTO.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    private func quote(of dto: InboundMessageDTO) throws -> MessageDataItem {
        let model = try XCTUnwrap(MessageModelMapper.toModel(from: dto, fieldCrypto: crypto))
        guard case .message(let quoted?) = MessageModelMapper.toDomain(model, fieldCrypto: crypto).reply else {
            XCTFail("reply expected")
            throw XCTSkip("no reply")
        }
        return quoted
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
