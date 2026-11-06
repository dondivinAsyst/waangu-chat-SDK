import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// A shared contact crosses the same four representations a poll does, but with
/// two shapes on the wire: the `contacts` array this app sends, and the flat
/// `contactName` / `contactPhone` / `userId` / `avatar` fields Android sends.
///
/// The flat shape used to lose the account id and the photo on the way in, which
/// only became visible on a forward — the copy is built from what the mapper
/// kept, so anything dropped here is dropped for good.
final class ContactContentCodecTests: XCTestCase {

    /// Verbatim from the wire, `content` nested as an object rather than a
    /// string — both spellings arrive, and this is the one Android sends.
    private let inboundEnvelope = """
    {
      "senderId": "110691817141112601",
      "senderName": "JAKIN IRISA",
      "senderPhone": "098741201",
      "senderAvatar": "",
      "receiverId": "611768bb8b70e0c342bedd7b",
      "conversationId": "f3c02768-b6e0-3087-a9ee-cbda6975873a",
      "codeMessage": "bf353997-1ee8-40bd-94df-734f5cdaacc1",
      "content": {
        "userId": "100000000000000001",
        "contactName": "DANY LEAD ANDROID",
        "contactPhone": "0911311300",
        "isRegistered": true,
        "avatar": "https://bucket.s3.us-east-1.amazonaws.com/avatars/dany.jpg"
      },
      "typeMessage": "CONTACT",
      "status": "PENDING",
      "forwarded": false,
      "viewOnce": false,
      "isMoney": false,
      "isMessageSystem": false,
      "sessionId": "ef1b7ad7-b2e7-433f-afa3-55c8c48c356c"
    }
    """

    private func storedContent(from envelope: String) throws -> MessageContentModel {
        let dto = try JSONDecoder().decode(
            InboundMessageDTO.self,
            from: Data(envelope.utf8)
        )
        return MessageModelMapper.mapInboundContent(
            dto.messageContent,
            type: .contact,
            fieldCrypto: PassthroughFieldCrypto()
        )
    }

    // MARK: - Inbound, flat shape

    func test_flatContactKeepsAccountIdAndAvatar() throws {
        let content = try storedContent(from: inboundEnvelope)

        let contact = try XCTUnwrap(content.contacts?.first)
        XCTAssertEqual(content.contacts?.count, 1)
        XCTAssertEqual(contact.userId, "100000000000000001")
        XCTAssertEqual(contact.name, "DANY LEAD ANDROID")
        XCTAssertEqual(contact.phone, "0911311300")
        XCTAssertEqual(contact.avatar, "https://bucket.s3.us-east-1.amazonaws.com/avatars/dany.jpg")
        XCTAssertEqual(contact.isRegistered, true)

        // The flat fields stay beside the array they were expanded into, so a
        // reader that only knows them still renders the card.
        XCTAssertEqual(content.contactName, "DANY LEAD ANDROID")
        XCTAssertEqual(content.contactPhone, "0911311300")
    }

    /// A sender with no photo sends its bucket root — base URL, empty key. That
    /// is not an avatar, and handing it to the image view fails to load instead
    /// of drawing the initials placeholder.
    func test_bucketRootAvatarReadsAsAbsent() throws {
        let envelope = inboundEnvelope.replacingOccurrences(
            of: "https://bucket.s3.us-east-1.amazonaws.com/avatars/dany.jpg",
            with: "https://digital-wallet-sandbox-bucket.s3.us-east-1.amazonaws.com/"
        )

        let content = try storedContent(from: envelope)

        XCTAssertEqual(content.contacts?.first?.userId, "100000000000000001")
        XCTAssertNil(content.contacts?.first?.avatar)
    }

    /// The array shape is authoritative wherever it exists: no flat field may
    /// overwrite a selection of several contacts with its first one.
    func test_contactsArrayWinsOverFlatFields() throws {
        let envelope = """
        {
          "senderId": "s1",
          "senderName": "Sender",
          "conversationId": "c1",
          "codeMessage": "m1",
          "content": {
            "contactName": "First Only",
            "contactPhone": "0911311300",
            "userId": "flat-id",
            "contacts": [
              {"id": "1", "userId": "u-one", "phone": "0911311300", "name": "One", "isRegistered": true},
              {"id": "2", "userId": "u-two", "phone": "0922422400", "name": "Two", "isRegistered": false}
            ]
          },
          "typeMessage": "CONTACT"
        }
        """

        let content = try storedContent(from: envelope)

        XCTAssertEqual(content.contacts?.count, 2)
        XCTAssertEqual(content.contacts?.map(\.userId), ["u-one", "u-two"])
    }

    // MARK: - Round trip: what a forward republishes

    func test_forwardedContactCarriesTheAccountIdOnward() throws {
        let stored = try storedContent(from: inboundEnvelope)
        let model = MessageModel(
            id: "bf353997-1ee8-40bd-94df-734f5cdaacc1",
            conversationId: "f3c02768-b6e0-3087-a9ee-cbda6975873a",
            senderId: "110691817141112601",
            senderName: "JAKIN IRISA",
            type: .contact,
            content: stored
        )

        // Read back the way the room reads it — this is the content a forward copies.
        let domain = MessageModelMapper.toDomain(model, fieldCrypto: PassthroughFieldCrypto())
        let forwarded = try XCTUnwrap(domain.message.contact?.first)
        XCTAssertEqual(forwarded.userId, "100000000000000001")
        XCTAssertEqual(forwarded.avatar, "https://bucket.s3.us-east-1.amazonaws.com/avatars/dany.jpg")

        // …and re-published, in both shapes, so neither kind of reader loses it.
        let outbound = MessageContentWireCodec.buildContentDTO(from: domain)
        XCTAssertEqual(outbound.userId, "100000000000000001")
        XCTAssertEqual(outbound.avatar, "https://bucket.s3.us-east-1.amazonaws.com/avatars/dany.jpg")
        XCTAssertEqual(outbound.contacts?.first?.userId, "100000000000000001")
        XCTAssertEqual(outbound.contactName, "DANY LEAD ANDROID")
        XCTAssertEqual(outbound.contactPhone, "0911311300")
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
