//
//  ReversalHistoryTests.swift
//  FeatureChatTests
//
//  TEST-REVERSAL-001 — Harness Bloc 3 §3 (B39) : une annulation par le
//  prestataire préserve l'opération d'origine. Elle ne l'efface pas, ne la
//  réécrit pas, et ne peut pas être réécrite en succès.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class ReversalHistoryTests: XCTestCase {

    private func card(_ version: Int, _ status: PaymentStatus) -> FinancialCardPayload {
        FinancialCardPayload(reference: FinanceFixtures.reference(id: "pay-42", version: version),
                             status: status, amount: 1500, currency: "BIF")
    }

    /// Le paiement d'origine reste à l'écran, avec son identité et son montant :
    /// seule son issue change.
    func test_reversal_keepsTheOriginalOperation_identityAndAmount() async {
        let store = FinancialObjectStore()
        _ = await store.apply(card(1, .completed))
        let applied = await store.apply(card(2, .reversed))

        XCTAssertTrue(applied)
        let current = await store.current(for: FinanceFixtures.reference(id: "pay-42"))
        XCTAssertEqual(current?.reference.id, "pay-42")
        XCTAssertEqual(current?.amount, 1500)
        XCTAssertEqual(current?.currency, "BIF")
        XCTAssertEqual(current?.status, .reversed)
        XCTAssertEqual(current?.presentation, .reversed, "Shown as reversed, not hidden and not settled")
    }

    /// Une révision plus récente qui prétend « terminé » après l'annulation est
    /// refusée : l'histoire ne se réécrit pas, une réconciliation est demandée.
    func test_reversedOperation_cannotBeRewrittenIntoASuccess() async {
        let store = FinancialObjectStore()
        _ = await store.apply(card(1, .completed))
        _ = await store.apply(card(2, .reversed))

        for (version, status) in [(3, PaymentStatus.completed), (4, .confirmed)] {
            let applied = await store.apply(card(version, status))
            XCTAssertFalse(applied, "\(status) accepted after a reversal")
        }
        let current = await store.current(for: FinanceFixtures.reference(id: "pay-42"))
        XCTAssertEqual(current?.status, .reversed)
        let forbidden = await store.forbiddenTransitionCount
        XCTAssertEqual(forbidden, 2)
    }

    /// Le seul prolongement d'une annulation est une contestation.
    func test_reversal_canOnlyBeFollowedByADispute() {
        XCTAssertEqual(FinancialObjectStateMachine.verdict(from: .completed, to: .reversed), .allowed)
        XCTAssertEqual(FinancialObjectStateMachine.verdict(from: .reversed, to: .disputed), .allowed)
        for next in [PaymentStatus.completed, .confirmed, .processing, .refunded] {
            guard case .forbidden = FinancialObjectStateMachine.verdict(from: .reversed, to: next) else {
                return XCTFail("reversed → \(next) should be forbidden")
            }
        }
    }
}
