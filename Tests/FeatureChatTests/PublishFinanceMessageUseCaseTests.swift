import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// A payment announced outside an open room follows the ordinary message path:
/// the discussion is created if missing, then the message is published — once.
final class PublishFinanceMessageUseCaseTests: XCTestCase {

    private var discussions: FakeDiscussionUseCases!
    private var outgoing: FakePublishOutgoingMessage!
    private var useCase: PublishFinanceMessageUseCase!

    override func setUp() {
        super.setUp()
        discussions = FakeDiscussionUseCases()
        outgoing = FakePublishOutgoingMessage()
        useCase = PublishFinanceMessageUseCase(
            discussions: discussions,
            messages: FakeMessagesUseCases(),
            publishOutgoing: outgoing,
            objects: FakeFinancialObjects(),
            // Same source the outgoing message builder stamps as `senderId`.
            currentUserId: { CurrentSessionInfo.shared.currentUid }
        )
    }

    private func target(conversationId: String = "conv-1", kind: ConversationKind = .direct) -> FinanceMessageTarget {
        FinanceMessageTarget(
            conversationId: conversationId,
            kind: kind,
            receiverUserId: "peer-1",
            contact: ContactChannel(phone: "+257 79 000 000", isBlocked: false, userId: "peer-1")
        )
    }

    func test_publishesIntoTheGivenConversationAndCreatesItsDiscussion() async throws {
        let reference = FinanceFixtures.reference(id: "pay-1")

        let message = try await useCase.execute(reference, to: target(), onLocallySaved: nil)

        XCTAssertEqual(message.transactionId, "pay-1")
        XCTAssertEqual(message.receiverId, "peer-1")
        XCTAssertEqual(discussions.creator.created.map(\.conversationId), ["conv-1"])
        XCTAssertEqual(discussions.creator.created.first?.contact?.userId, "peer-1")
        XCTAssertEqual(outgoing.published.map(\.conversationId), ["conv-1"])
        XCTAssertEqual(outgoing.published.first?.codeMessage, message.codeMessage)
    }

    func test_directMessageCarriesNoGroupId_groupMessageCarriesTheConversation() async throws {
        let direct = try await useCase.execute(
            FinanceFixtures.reference(id: "a"), to: target(conversationId: "d"), onLocallySaved: nil)
        let group = try await useCase.execute(
            FinanceFixtures.reference(id: "b"), to: target(conversationId: "g", kind: .group), onLocallySaved: nil)

        XCTAssertNil(direct.groupId)
        XCTAssertEqual(group.groupId, "g")
    }

    func test_referenceAlreadyAnnouncedIsNeverDuplicated() async throws {
        let reference = FinanceFixtures.reference(id: "pay-1")
        let existing = FinanceConversationMessage.make(
            reference: reference, payload: nil, groupID: nil, receiverID: "peer-1")
        discussions.messages.byConversation["conv-1"] = [existing]

        let message = try await useCase.execute(reference, to: target(), onLocallySaved: nil)

        XCTAssertEqual(message.codeMessage, existing.codeMessage)
        XCTAssertTrue(discussions.creator.created.isEmpty, "no second discussion row")
        // Still pending → republished, not recreated.
        XCTAssertEqual(outgoing.published.map(\.codeMessage), [existing.codeMessage])
    }

    /// The receiver cannot read the object (`SELF` is owner-only): what goes
    /// out is all they get. Unknown locally ⇒ read first, then publish full.
    func test_objectUnknownLocally_isReadBeforePublishing_andGoesOutComplete() async throws {
        let reference = FinanceFixtures.reference(type: .moneyRequest, id: "req-1", version: 2)
        let served = FinancialCardPayload(reference: reference, status: .pending,
                                          amount: 2_000_000, currency: "BIF", verification: .verified)
        useCase = PublishFinanceMessageUseCase(
            discussions: discussions, messages: FakeMessagesUseCases(), publishOutgoing: outgoing,
            objects: FakeFinancialObjects(served: served),
            currentUserId: { CurrentSessionInfo.shared.currentUid })

        _ = try await useCase.execute(reference, note: "Payment for car", to: target(), onLocallySaved: nil)

        let sent = try XCTUnwrap(outgoing.messages.first)
        let wire = MessageContentWireCodec.decode(MessageContentWireCodec.encode(from: sent),
                                                  typeMessage: "ISMONEY")
        XCTAssertEqual(wire.text, "Payment for car")
        XCTAssertEqual(wire.paymentRef, "req-1")
        XCTAssertEqual(wire.financialObjectType, "MONEY_REQUEST")
        XCTAssertEqual(wire.financialObjectVersion, 2)
        XCTAssertEqual(wire.paymentAmount, 2_000_000)
        XCTAssertEqual(wire.paymentCurrency, "BIF")
        XCTAssertEqual(wire.paymentStatus, "PENDING")
    }

    /// Server unreachable: the message still goes out, as a reference.
    func test_readFails_stillPublishes_referenceOnly() async throws {
        let reference = FinanceFixtures.reference(type: .payment, id: "pay-9")
        _ = try await useCase.execute(reference, to: target(), onLocallySaved: nil)

        let sent = try XCTUnwrap(outgoing.messages.first)
        let wire = MessageContentWireCodec.decode(MessageContentWireCodec.encode(from: sent),
                                                  typeMessage: "ISMONEY")
        XCTAssertEqual(wire.financialObjectType, "PAYMENT")
        XCTAssertNil(wire.paymentAmount)
    }

    func test_reportsTheLocallySavedMessageBeforePublishing() async throws {
        var saved: [String] = []
        _ = try await useCase.execute(FinanceFixtures.reference(id: "pay-1"), to: target()) { items in
            saved.append(contentsOf: items.compactMap(\.transactionId))
        }
        XCTAssertEqual(saved, ["pay-1"])
    }

    func test_emptyConversationIdIsRefused() async {
        do {
            _ = try await useCase.execute(
                FinanceFixtures.reference(), to: target(conversationId: ""), onLocallySaved: nil)
            XCTFail("expected missingConversation")
        } catch {
            XCTAssertEqual(error as? PublishFinanceMessageError, .missingConversation)
        }
        XCTAssertTrue(outgoing.published.isEmpty)
    }
}
