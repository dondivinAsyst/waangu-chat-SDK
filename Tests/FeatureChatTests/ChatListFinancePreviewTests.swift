import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// A finance message as a conversation's last message used to leave the row
/// empty: it has no text, and the row's switch fell through to `default`.
final class ChatListFinancePreviewTests: XCTestCase {

    private func message(type: FinancialObjectType?, amount: Decimal = 50_000) -> MessageDataItem {
        let reference = FinanceFixtures.reference(type: type ?? .payment)
        let payload = type.map { _ in
            FinancialCardPayload(reference: reference, status: .confirmed,
                                 amount: amount, currency: "BIF", verification: .verified)
        }
        return FinanceConversationMessage.make(reference: reference, payload: payload,
                                               groupID: nil, receiverID: "peer")
    }

    private func translate(_ key: String) -> String { key }

    func test_paymentShowsItsKindAndAmount() {
        let preview = ChatListFinancePreview(message: message(type: .payment))
        XCTAssertEqual(preview.titleKey, ChatTranslationKeys.MEDIA_TYPE_PAYMENT)
        XCTAssertEqual(preview.systemImage, "banknote.fill")
        XCTAssertNotNil(preview.amount)
        XCTAssertTrue(preview.subtitle(translate: translate).hasPrefix("media_type_payment · "))
        XCTAssertTrue(preview.subtitle(translate: translate).hasSuffix("BIF"))
    }

    func test_eachKindGetsItsOwnLabel() {
        XCTAssertEqual(ChatListFinancePreview(message: message(type: .moneyRequest)).titleKey,
                       ChatTranslationKeys.MEDIA_TYPE_MONEY_REQUEST)
        XCTAssertEqual(ChatListFinancePreview(message: message(type: .splitBill)).titleKey,
                       ChatTranslationKeys.MEDIA_TYPE_SPLIT_BILL)
        XCTAssertEqual(ChatListFinancePreview(message: message(type: .refund)).titleKey,
                       ChatTranslationKeys.MEDIA_TYPE_REFUND)
        XCTAssertEqual(ChatListFinancePreview(message: message(type: .airtime)).titleKey,
                       ChatTranslationKeys.MEDIA_TYPE_RECHARGE)
        XCTAssertEqual(ChatListFinancePreview(message: message(type: .dataBundle)).titleKey,
                       ChatTranslationKeys.MEDIA_TYPE_RECHARGE)
        // Merchant payments and cash movements read as payments.
        XCTAssertEqual(ChatListFinancePreview(message: message(type: .cashOut)).titleKey,
                       ChatTranslationKeys.MEDIA_TYPE_PAYMENT)
        XCTAssertEqual(ChatListFinancePreview(message: message(type: .merchantPayment)).titleKey,
                       ChatTranslationKeys.MEDIA_TYPE_PAYMENT)
    }

    /// A reference-only card has no server amount yet — the row must not invent one.
    func test_pendingCardShowsTheKindWithoutAnAmount() {
        let preview = ChatListFinancePreview(message: message(type: nil))
        XCTAssertEqual(preview.titleKey, ChatTranslationKeys.MEDIA_TYPE_PAYMENT)
        XCTAssertNil(preview.amount)
        XCTAssertEqual(preview.subtitle(translate: translate), "media_type_payment")
    }
}
