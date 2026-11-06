//
//  RefundLifecycleTests.swift
//  FeatureChatTests
//
//  Chapitre 24 — les quatre états ajoutés, et le risque transversal 9 ↔ 12.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class RefundLifecycleTests: XCTestCase {

    private let refundCycle: [PaymentStatus] = [
        .refundRequested, .refundApproved, .refundProcessing
    ]

    // MARK: - Sémantique

    /// **Le point du chapitre 24.** `refundApproved` n'est pas `refunded` :
    /// l'argent n'est pas revenu. Les confondre annoncerait un remboursement
    /// reçu qui peut encore échouer.
    func test_approvedIsNotRefunded() {
        XCTAssertNotEqual(PaymentStatus.refundApproved, .refunded)
        XCTAssertFalse(PaymentStatus.refundApproved.isTerminal)
        XCTAssertTrue(PaymentStatus.refunded.isTerminal)
    }

    func test_refundCycleIsInFlightNotTerminal() {
        for status in refundCycle {
            XCTAssertTrue(status.isInFlight, "\(status) évolue encore")
            XCTAssertFalse(status.isTerminal, "\(status) n'est pas final")
        }
    }

    func test_reconcilingIsInFlight() {
        XCTAssertTrue(PaymentStatus.reconciling.isInFlight)
        XCTAssertFalse(PaymentStatus.reconciling.isTerminal)
    }

    // MARK: - Le risque transversal 9 ↔ 12

    /// **La règle que je me suis imposée au Bloc 2** : toute dimension d'état
    /// ajoutée passe par `presentation`. Aucun des quatre nouveaux états ne doit
    /// pouvoir annoncer un succès.
    func test_noNewStateCanAnnounceSuccess() {
        for status in refundCycle + [.reconciling] {
            for verification in [FinancialCardVerification.verified, .unverified, .rejected] {
                let payload = FinancialCardPayloadFixture.make(
                    status: status, verification: verification
                )
                XCTAssertFalse(
                    payload.presentation.announcesSuccess,
                    "\(status) / \(verification) ne doit jamais annoncer un succès"
                )
            }
        }
    }

    /// Le cycle de remboursement a son propre traitement, distinct du succès
    /// **et** distinct du remboursement abouti.
    func test_refundCycleHasItsOwnTreatment() {
        for status in refundCycle {
            let payload = FinancialCardPayloadFixture.make(status: status, verification: .verified)
            XCTAssertEqual(payload.presentation, .refundInProgress, "\(status)")
        }
        let done = FinancialCardPayloadFixture.make(status: .refunded, verification: .verified)
        XCTAssertEqual(done.presentation, .refunded, "l'abouti reste distinct de l'en-cours")
    }

    func test_reconcilingHasItsOwnTreatment() {
        let payload = FinancialCardPayloadFixture.make(status: .reconciling, verification: .verified)
        XCTAssertEqual(payload.presentation, .reconciling)
    }

    /// La répudiation continue de tout emporter, y compris les états neufs.
    func test_repudiationStillOverridesNewStates() {
        for status in refundCycle + [.reconciling] {
            let payload = FinancialCardPayloadFixture.make(status: status, verification: .rejected)
            XCTAssertEqual(payload.presentation, .repudiated, "\(status)")
        }
    }

    // MARK: - Transitions

    /// Un paiement abouti peut entrer dans le cycle de remboursement.
    func test_completedMayEnterRefundCycle() {
        XCTAssertEqual(
            FinancialObjectStateMachine.verdict(from: .completed, to: .refundRequested),
            .allowed
        )
        XCTAssertEqual(
            FinancialObjectStateMachine.verdict(from: .completed, to: .reconciling),
            .allowed
        )
    }

    /// Le cycle avance dans l'ordre décidé par le backend, sans que le client
    /// n'en déduise l'étape suivante.
    func test_refundCycleProgressesForward() {
        let steps: [(PaymentStatus, PaymentStatus)] = [
            (.refundRequested, .refundApproved),
            (.refundApproved, .refundProcessing),
            (.refundProcessing, .refunded),
            // Un remboursement accordé peut encore échouer : c'est précisément
            // pourquoi `refundApproved` n'est pas `refunded`.
            (.refundApproved, .failed),
            (.refundProcessing, .failed)
        ]
        for (from, to) in steps {
            XCTAssertEqual(
                FinancialObjectStateMachine.verdict(from: from, to: to), .allowed,
                "\(from) -> \(to)"
            )
        }
    }

    /// Un remboursement abouti ne redevient pas un paiement abouti.
    func test_refundedNeverBecomesCompleted() {
        guard case .forbidden = FinancialObjectStateMachine.verdict(from: .refunded, to: .completed)
        else { return XCTFail("refunded -> completed doit être refusé") }
    }

    /// Le décodage défensif couvre aussi les états neufs.
    func test_newStatesDecodeExactly() throws {
        let pairs: [(String, PaymentStatus)] = [
            ("REFUND_REQUESTED", .refundRequested),
            ("REFUND_APPROVED", .refundApproved),
            ("REFUND_PROCESSING", .refundProcessing),
            ("RECONCILING", .reconciling)
        ]
        for (raw, expected) in pairs {
            let decoded = try JSONDecoder().decode(
                PaymentStatus.self, from: Data("\"\(raw)\"".utf8)
            )
            XCTAssertEqual(decoded, expected)
        }
    }
}
