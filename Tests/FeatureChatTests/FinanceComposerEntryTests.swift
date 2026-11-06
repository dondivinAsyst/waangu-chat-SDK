import XCTest
import UIKit
@testable import WaanguFeatureChat

@MainActor
final class FinanceComposerEntryTests: XCTestCase {
    func testPaymentActionIsOptionalAndDoesNotSubmitOrClearText() {
        let bar = TextInputToolbarAreaView(frame: CGRect(x: 0, y: 0, width: 393, height: 60))
        var opened = 0
        var messagesSent = 0
        bar.onSendMessage = { _ in messagesSent += 1 }
        bar.textField.text = "Unsent conversation draft"
        bar.configurePayments(action: { opened += 1 }, label: "Payments")
        bar.layoutIfNeeded()
        XCTAssertFalse(bar.paymentButton.isHidden)
        XCTAssertGreaterThanOrEqual(bar.paymentButton.bounds.width, 44)
        XCTAssertEqual(bar.paymentButton.accessibilityLabel, "Payments")
        tap(bar.paymentButton)
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(messagesSent, 0)
        XCTAssertEqual(bar.textField.text, "Unsent conversation draft")

        bar.configurePayments(action: nil, label: "Payments")
        bar.layoutIfNeeded()
        XCTAssertTrue(bar.paymentButton.isHidden)
        XCTAssertEqual(bar.paymentButton.bounds.width, 0)
    }

    /// Runs the button's registered touch-up actions.
    ///
    /// `sendActions(for:)` routes through `UIApplication`, which does not exist
    /// in a package test bundle ("UIApp is nil … cannot dispatch control
    /// actions"): the tap was silently dropped and the test read `opened == 0`.
    /// Invoking the registered target-action still proves the button is wired.
    private func tap(_ button: UIButton) {
        for target in button.allTargets {
            for action in button.actions(forTarget: target, forControlEvent: .touchUpInside) ?? [] {
                _ = (target as NSObject).perform(Selector(action))
            }
        }
    }
}
