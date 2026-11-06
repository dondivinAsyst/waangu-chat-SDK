//
//  InDoubtParityTests.swift
//  FeatureChatTests
//
//  TEST-INDOUBT-001 — Harness Bloc 2 §28, §29, §62 (M3).
//  `IN_DOUBT` reste une valeur à part entière, identique au mot canonique, et
//  se conduit comme une incertitude : vérifier, jamais rejouer, jamais échouer.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class InDoubtParityTests: XCTestCase {

    func test_serverWord_isKeptAsTheCanonicalValue() {
        XCTAssertEqual(FcoCardMapper.paymentStatus("IN_DOUBT"), .inDoubt)
        XCTAssertEqual(FcoCardMapper.paymentStatus("in_doubt"), .inDoubt, "Casse indifférente")
        XCTAssertEqual(PaymentStatus.inDoubt.rawValue, "IN_DOUBT", "Même mot sur Android, iOS et Web")
        XCTAssertEqual(FcoCardMapper.paymentStatus("UNKNOWN"), .unknown, "UNKNOWN reste distinct")
    }

    func test_decodesFromTheWire() throws {
        let status = try JSONDecoder().decode([PaymentStatus].self, from: Data(#"["IN_DOUBT"]"#.utf8))
        XCTAssertEqual(status, [.inDoubt])
    }

    /// §62 : actionability — rafraîchir le statut, jamais rejouer.
    func test_behavesAsUncertainty_neverAsFailureOrRetry() {
        let status = PaymentStatus.inDoubt
        XCTAssertTrue(status.requiresReconciliation)
        XCTAssertFalse(status.isTerminal)
        XCTAssertFalse(status.isInFlight)
        XCTAssertEqual(FinancialTruth.from(status), .unknown)
        XCTAssertTrue(FinancialTruth.from(status).requiresRequery)
        XCTAssertFalse(FinancialTruth.from(status).permitsRetry)
    }

    func test_cardPresentsVerification_notFailure() {
        let card = FinancialCardPayload(reference: FinanceFixtures.reference(version: 1),
                                        status: .inDoubt, amount: 1000, currency: "BIF")
        XCTAssertEqual(card.presentation, .verifying)
        XCTAssertTrue(card.needsReconciliation)
    }

    /// Entrer en doute et en sortir sont toujours licites, comme pour `unknown`.
    func test_stateMachine_allowsEnteringAndLeavingDoubt() {
        XCTAssertEqual(FinancialObjectStateMachine.verdict(from: .processing, to: .inDoubt), .allowed)
        XCTAssertEqual(FinancialObjectStateMachine.verdict(from: .inDoubt, to: .completed), .allowed)
    }

    /// Avant M3, un paiement en doute s'affichait « État non reconnu par cette version ».
    func test_label_saysVerification_notUnrecognised() {
        XCTAssertNotEqual(FinanceStrings.paymentStatusLabel(.inDoubt), FinanceStrings.paymentStatusLabel(.unknown))
    }
}
