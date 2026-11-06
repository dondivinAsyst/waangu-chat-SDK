import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceConversationMessageTests: XCTestCase {
    func testReferenceOnlySubmissionSurvivesStorageAndWireWithoutInventedAmount() {
        for type in [FinancialObjectType.payment, .moneyRequest] {
            let reference = FinanceFixtures.reference(type: type)
            let message = FinanceConversationMessage.make(reference: reference, payload: nil,
                                                          groupID: nil, receiverID: "recipient")
            XCTAssertTrue(message.isMoney)
            XCTAssertEqual(message.typeMessage, .ISMONEY)
            XCTAssertEqual(message.receiverId, "recipient")
            XCTAssertNil(message.message.financial)
            XCTAssertNil(message.reply)

            let model = MessageModelMapper.toModel(from: message, conversationId: "chat",
                                                   fieldCrypto: FinanceTestFieldCrypto())
            let restored = MessageModelMapper.toDomain(model, fieldCrypto: FinanceTestFieldCrypto())
            XCTAssertEqual(restored.transactionId, reference.id)
            XCTAssertEqual(restored.typeMessage, .ISMONEY)
            XCTAssertNil(restored.message.financial)

            let wire = MessageContentWireCodec.decode(MessageContentWireCodec.encode(from: message),
                                                      typeMessage: "ISMONEY")
            XCTAssertEqual(wire.paymentRef, reference.id)
            XCTAssertNil(wire.paymentAmount)
            XCTAssertNil(wire.paymentCurrency)
            XCTAssertNil(wire.paymentStatus)
        }
    }

    /// Le motif dit au destinataire à quoi sert l'argent : il voyage comme le
    /// **texte** du message — le contrat de paiement n'a pas de champ pour lui —
    /// et doit survivre à la base comme au fil.
    func testNoteTravelsAsTheMessageTextAndReachesTheWire() {
        let reference = FinanceFixtures.reference()
        let message = FinanceConversationMessage.make(reference: reference, note: "  Gigot man  ",
                                                      payload: nil, groupID: nil, receiverID: "recipient")
        XCTAssertEqual(message.message.text, "Gigot man", "Espaces superflus retirés")

        let model = MessageModelMapper.toModel(from: message, conversationId: "chat",
                                               fieldCrypto: FinanceTestFieldCrypto())
        let restored = MessageModelMapper.toDomain(model, fieldCrypto: FinanceTestFieldCrypto())
        XCTAssertEqual(restored.message.text, "Gigot man")

        let wire = MessageContentWireCodec.decode(MessageContentWireCodec.encode(from: message),
                                                  typeMessage: "ISMONEY")
        XCTAssertEqual(wire.text, "Gigot man", "Le destinataire reçoit le motif")
        XCTAssertEqual(wire.paymentRef, reference.id)
    }

    /// La bulle dessine la note sous la carte : les deux doivent coexister,
    /// sans que le montant ne chasse le texte ni l'inverse.
    func testNoteAndCardTravelTogether() {
        let reference = FinanceFixtures.reference()
        let payload = FinancialCardPayload(reference: reference, status: .confirmed,
                                           amount: 50_000, currency: "BIF",
                                           verification: .verified)
        let message = FinanceConversationMessage.make(reference: reference, note: "Loyer de septembre",
                                                      payload: payload, groupID: nil, receiverID: "recipient")

        let restored = MessageModelMapper.toDomain(
            MessageModelMapper.toModel(from: message, conversationId: "chat",
                                       fieldCrypto: FinanceTestFieldCrypto()),
            fieldCrypto: FinanceTestFieldCrypto())
        XCTAssertEqual(restored.message.text, "Loyer de septembre")
        XCTAssertEqual(restored.message.financial?.amount, 50_000)

        let wire = MessageContentWireCodec.decode(MessageContentWireCodec.encode(from: message),
                                                  typeMessage: "ISMONEY")
        XCTAssertEqual(wire.text, "Loyer de septembre")
        XCTAssertEqual(wire.paymentAmount, 50_000)
        XCTAssertEqual(wire.paymentCurrency, "BIF")
        XCTAssertEqual(wire.paymentRef, reference.id)
    }

    /// Le destinataire reconstruit la carte depuis le fil — bonne nature, bon
    /// montant — sans jamais la tenir pour vérifiée : le montant vient de
    /// l'expéditeur, pas du backend.
    func testReceiverRebuildsTheCardFromTheWire_unverified() {
        for type in [FinancialObjectType.payment, .moneyRequest] {
            let reference = FinanceFixtures.reference(type: type, version: 4)
            let payload = FinancialCardPayload(reference: reference, status: .completed,
                                               amount: 50_000, currency: "BIF",
                                               verification: .verified)
            let sent = FinanceConversationMessage.make(reference: reference, payload: payload,
                                                       groupID: nil, receiverID: "recipient")

            let wire = MessageContentWireCodec.decode(MessageContentWireCodec.encode(from: sent),
                                                      typeMessage: "ISMONEY")
            let stored = MessageModelMapper.mapInboundContent(wire, type: .payment,
                                                              fieldCrypto: FinanceTestFieldCrypto())
            let card = MessageModelMapper.buildFinancial(from: stored)

            XCTAssertEqual(card?.reference.type, type, "La carte choisie est celle de l'objet envoyé")
            XCTAssertEqual(card?.reference.id, reference.id)
            XCTAssertEqual(card?.reference.version, 4)
            XCTAssertEqual(card?.amount, 50_000)
            XCTAssertEqual(card?.currency, "BIF")
            XCTAssertEqual(card?.verification, .unverified, "Jamais vérifié sur la seule foi du fil")
            XCTAssertEqual(card?.presentation.announcesSuccess, false)
        }
    }

    /// Une demande part avant que sa carte soit lue : sa nature doit partir
    /// quand même, et survivre à la base — sinon le destinataire la lisait
    /// comme un paiement reçu.
    func testRequestPublishedBeforeItsCardStillCarriesItsType() {
        let reference = FinanceFixtures.reference(type: .moneyRequest, id: "req-1")
        let message = FinanceConversationMessage.make(reference: reference, payload: nil,
                                                      groupID: nil, receiverID: "peer")

        let wire = MessageContentWireCodec.decode(MessageContentWireCodec.encode(from: message),
                                                  typeMessage: "ISMONEY")
        XCTAssertEqual(wire.financialObjectType, "MONEY_REQUEST")
        XCTAssertNil(wire.financialObjectVersion, "La révision ne vient que de la carte")
        XCTAssertNil(wire.paymentAmount, "Aucun montant inventé")

        let restored = MessageModelMapper.toDomain(
            MessageModelMapper.toModel(from: message, conversationId: "chat",
                                       fieldCrypto: FinanceTestFieldCrypto()),
            fieldCrypto: FinanceTestFieldCrypto())
        XCTAssertEqual(restored.message.financialObjectType, .moneyRequest)

        let received = MessageModelMapper.mapInboundContent(wire, type: .payment,
                                                            fieldCrypto: FinanceTestFieldCrypto())
        XCTAssertEqual(ChatSyncDelegate.financialReference(
            of: MessageModel(conversationId: "c", senderId: "me", senderName: "Moi",
                             type: .payment, content: received))?.type, .moneyRequest)
    }

    /// Un client qui n'envoie pas encore la nature de l'objet garde la carte
    /// d'attente : pas de type deviné.
    func testWireWithoutObjectTypeKeepsThePendingCard() {
        let wire = MessageContentWireCodec.decode(
            #"{"paymentRef":"obj-1","paymentAmount":50000,"paymentCurrency":"BIF","paymentStatus":"COMPLETED"}"#,
            typeMessage: "ISMONEY")
        let stored = MessageModelMapper.mapInboundContent(wire, type: .payment,
                                                          fieldCrypto: FinanceTestFieldCrypto())
        XCTAssertNil(MessageModelMapper.buildFinancial(from: stored))
    }

    /// Sans motif, rien n'est ajouté : pas de texte vide sur le fil.
    func testWithoutANoteTheMessageCarriesNoText() {
        let message = FinanceConversationMessage.make(reference: FinanceFixtures.reference(), note: "   ",
                                                      payload: nil, groupID: nil, receiverID: "recipient")
        XCTAssertTrue(message.message.text.isEmpty)
        let wire = MessageContentWireCodec.decode(MessageContentWireCodec.encode(from: message),
                                                  typeMessage: "ISMONEY")
        XCTAssertNil(wire.text)
    }

    func testExistingProjectionRetainsRevisionAndVerificationLocally() {
        let reference = FinanceFixtures.reference(version: 7)
        let payload = FinancialCardPayload(reference: reference, status: .confirmed,
                                           amount: Decimal(string: "12.35")!, currency: "USD",
                                           verification: .unverified)
        let message = FinanceConversationMessage.make(reference: reference, payload: payload,
                                                      groupID: "group", receiverID: "recipient")
        let model = MessageModelMapper.toModel(from: message, conversationId: "chat",
                                               fieldCrypto: FinanceTestFieldCrypto())
        let restored = MessageModelMapper.toDomain(model, fieldCrypto: FinanceTestFieldCrypto())
        XCTAssertEqual(restored.message.financial?.reference.version, 7)
        XCTAssertEqual(restored.message.financial?.amount, payload.amount)
        XCTAssertEqual(restored.message.financial?.verification, .unverified)
        XCTAssertEqual(restored.message.financial?.presentation.announcesSuccess, false)
        let wire = MessageContentWireCodec.buildContentDTO(from: message)
        XCTAssertEqual(wire.paymentRef, reference.id)
        XCTAssertEqual(wire.paymentAmount, 12.35)
        XCTAssertEqual(wire.paymentCurrency, "USD")
    }

    func testUnrelatedCachedProjectionCannotAppearOnSubmittedOperation() {
        let reference = FinanceFixtures.reference(id: "submitted")
        let other = FinancialCardPayload(reference: FinanceFixtures.reference(id: "other"),
                                         status: .completed, amount: 500, currency: "BIF",
                                         verification: .verified)
        let message = FinanceConversationMessage.make(reference: reference, payload: other,
                                                      groupID: nil, receiverID: "recipient")
        XCTAssertNil(message.message.financial)
        XCTAssertEqual(message.transactionId, "submitted")
    }
}

private struct FinanceTestFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }

    // Ajoutés au protocole après l'écriture de cette doublure, qui ne compilait
    // donc plus — et comme un seul module de test qui ne compile pas bloque
    // `build-for-testing`, c'est **toute** la suite qui ne tournait plus.
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
