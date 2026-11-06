import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Settings no longer opens a conversation before paying. It remembers the
/// existing conversation, announces into it — or into a new one — and opens
/// exactly that conversation afterwards.
@MainActor
final class WalletPaymentFlowViewModelTests: XCTestCase {

    private var discussions: FakeDiscussionUseCases!
    private var publisher: FakePublishFinanceMessage!
    private var model: WalletPaymentFlowViewModel!

    private let send = FinanceCatalogEntry(
        id: "send_money", kind: .sendMoney, titleKey: "entry_send_money",
        iconName: "arrow.up", isEnabled: true, unavailableReasonKey: nil
    )

    override func setUp() async throws {
        discussions = FakeDiscussionUseCases()
        publisher = FakePublishFinanceMessage()
        model = WalletPaymentFlowViewModel(
            discussions: discussions,
            publisher: publisher,
            makeConversationId: { "minted-conv" }
        )
    }

    func test_pickingAContactOpensNothing_itOnlyPreparesThePayment() async {
        XCTAssertTrue(model.begin(send))
        await model.picked(MessagingFixtures.contact(userId: "u-1", phone: "79000000"))

        XCTAssertNotNil(model.sheet?.payment, "form shown in the same sheet")
        XCTAssertNil(model.conversationToOpen(), "nothing to open before an announcement")
    }

    func test_existingConversationIsReusedWhateverTheNumberSpacing() async {
        discussions.list.items = [MessagingFixtures.directDiscussion(conversationId: "known", phone: "+257 79 00 00 00")]
        _ = model.begin(send)
        await model.picked(MessagingFixtures.contact(userId: "u-1", phone: "25779000000"))

        let published = await model.publish(FinanceFixtures.reference())
        XCTAssertTrue(published)
        model.close()

        XCTAssertEqual(publisher.targets.map(\.conversationId), ["known"])
        guard case .direct(_, let conversationId, _)? = model.conversationToOpen() else {
            return XCTFail("expected a direct conversation")
        }
        XCTAssertEqual(conversationId, "known")
    }

    /// The trap: if the room were opened without the minted id, it would mint a
    /// second one and the payment message would sit in a conversation not shown.
    func test_newConversationOpensWithTheSameIdTheMessageWasPublishedTo() async {
        _ = model.begin(send)
        await model.picked(MessagingFixtures.contact(userId: "u-2", phone: "79111111"))

        let published = await model.publish(FinanceFixtures.reference())
        XCTAssertTrue(published)
        model.close()

        XCTAssertEqual(publisher.targets.first?.conversationId, "minted-conv")
        XCTAssertEqual(publisher.targets.first?.receiverUserId, "u-2")
        guard case .direct(let phone, let conversationId, let peer)? = model.conversationToOpen() else {
            return XCTFail("expected a direct conversation")
        }
        XCTAssertEqual(conversationId, "minted-conv")
        XCTAssertEqual(phone, "79111111")
        XCTAssertEqual(peer?.userId, "u-2")
    }

    /// `send-money/prepare` exige un fil : une première conversation reçoit son
    /// identifiant dès le choix, et l'annonce vise ce même identifiant.
    func test_newContact_getsItsConversationIdBeforeThePrepare() async {
        _ = model.begin(send)
        await model.picked(MessagingFixtures.contact(userId: "u-2", phone: "79111111"))

        XCTAssertEqual(model.sheet?.payment?.recipient?.conversationId, "minted-conv")
        XCTAssertNil(model.sheet?.payment?.recipient?.existingConversationId)
        _ = await model.publish(FinanceFixtures.reference())
        XCTAssertEqual(publisher.targets.map(\.conversationId), ["minted-conv"])
    }

    /// Le fil existant se retrouve par l'utilisateur, même quand les numéros
    /// ne s'écrivent pas pareil (indicatif présent d'un côté seulement).
    func test_existingConversationIsFoundByUser_whateverThePhoneFormat() async {
        var discussion = MessagingFixtures.directDiscussion(conversationId: "known", phone: "79 00 00 00")
        discussion.contact?.userId = "u-1"
        discussions.list.items = [discussion]
        _ = model.begin(send)
        await model.picked(MessagingFixtures.contact(userId: "u-1", phone: "+25779000000"))

        XCTAssertEqual(model.sheet?.payment?.recipient?.conversationId, "known")
    }

    func test_cancellingOpensNoConversation() async {
        _ = model.begin(send)
        await model.picked(MessagingFixtures.contact(userId: "u-1", phone: "79000000"))
        model.close()

        XCTAssertNil(model.conversationToOpen())
        XCTAssertTrue(publisher.targets.isEmpty)
    }

    func test_qrRecipientHasNoConversationToAnnounceIn() async {
        _ = model.begin(send)
        model.pickedWalletHandle(.walletHandle("actor-9"))

        XCTAssertNil(model.sheet?.payment?.recipient)
        let published = await model.publish(FinanceFixtures.reference())
        XCTAssertFalse(published)
        XCTAssertTrue(publisher.targets.isEmpty)
    }

    func test_entriesWithoutRecipientAreLeftToTheCaller() {
        let cashIn = FinanceCatalogEntry(
            id: "cash_in", kind: .cashIn, titleKey: "entry_cash_in",
            iconName: "arrow.down", isEnabled: true, unavailableReasonKey: nil
        )
        XCTAssertFalse(model.begin(cashIn))
        XCTAssertNil(model.sheet)
    }
}
