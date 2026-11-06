//
//  FinancialStateMachineTests.swift
//  FeatureChatTests
//
//  Les transitions interdites, et le fait qu'elles soient réellement appliquées
//  par le magasin — pas seulement déclarées par la machine.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinancialStateMachineTests: XCTestCase {

    // MARK: - Les cinq interdictions énoncées

    /// Le cas d'école : une opération close repasserait en « en cours ».
    func test_completedNeverReturnsToProcessing() {
        XCTAssertEqual(
            FinancialObjectStateMachine.verdict(from: .completed, to: .processing),
            .forbidden(reason: "terminal_reopen(COMPLETED->PROCESSING)")
        )
    }

    func test_confirmedNeverReturnsToDraftLikeStates() {
        for target in [PaymentStatus.queued, .syncing, .pending, .processing] {
            guard case .forbidden = FinancialObjectStateMachine.verdict(from: .confirmed, to: target)
            else { return XCTFail("confirmed -> \(target) doit être refusé") }
        }
    }

    /// Un remboursement ne redevient pas un paiement abouti.
    func test_refundedNeverReturnsToCompleted() {
        guard case .forbidden = FinancialObjectStateMachine.verdict(from: .refunded, to: .completed)
        else { return XCTFail("refunded -> completed doit être refusé") }
    }

    /// Le montant, le taux et les frais d'un devis périmé ne sont plus ceux que
    /// l'utilisateur a acceptés.
    func test_expiredNeverBecomesPaid() {
        for target in [PaymentStatus.confirmed, .completed] {
            XCTAssertEqual(
                FinancialObjectStateMachine.verdict(from: .expired, to: target),
                .forbidden(reason: "expired_to_paid_without_new_quote")
            )
        }
    }

    func test_failedAndCancelledNeverReopen() {
        for origin in [PaymentStatus.failed, .cancelled, .denied, .restricted] {
            guard case .forbidden = FinancialObjectStateMachine.verdict(from: origin, to: .completed)
            else { return XCTFail("\(origin) -> completed doit être refusé") }
        }
    }

    // MARK: - Ce qui reste licite

    /// Les événements d'après-finalité sont la raison d'être des exceptions.
    func test_postFinalityTransitionsRemainAllowed() {
        let allowed: [(PaymentStatus, PaymentStatus)] = [
            (.confirmed, .completed), (.completed, .refunded),
            (.completed, .partiallyRefunded), (.completed, .reversed),
            (.completed, .disputed), (.partiallyRefunded, .refunded),
            (.refunded, .disputed), (.reversed, .disputed)
        ]
        for (from, to) in allowed {
            XCTAssertEqual(
                FinancialObjectStateMachine.verdict(from: from, to: to), .allowed,
                "\(from) -> \(to) doit rester licite"
            )
        }
    }

    /// Avouer son ignorance est licite depuis n'importe quel état — c'est ce qui
    /// permet à un timeout de dégrader proprement un objet sans être bloqué.
    func test_anyStateMayBecomeUnknown() {
        for status in PaymentStatus.allCases {
            XCTAssertEqual(
                FinancialObjectStateMachine.verdict(from: status, to: .unknown), .allowed,
                "\(status) -> unknown doit être licite"
            )
        }
    }

    /// Sortir de `unknown` est exactement ce que produit une réconciliation.
    func test_unknownMayResolveToAnything() {
        for status in PaymentStatus.allCases {
            XCTAssertEqual(
                FinancialObjectStateMachine.verdict(from: .unknown, to: status), .allowed,
                "unknown -> \(status) doit être licite"
            )
        }
    }

    func test_sameStateIsIdempotent() {
        for status in PaymentStatus.allCases {
            XCTAssertEqual(FinancialObjectStateMachine.verdict(from: status, to: status), .allowed)
        }
    }

    // MARK: - Application réelle par le magasin

    /// **Le test qui compte.** Une machine à états qu'aucun chemin d'écriture ne
    /// consulte ne protège rien — c'est le défaut de classe que le Bloc 1 a
    /// trouvé quatre fois.
    func test_storeRejectsForbiddenTransitionEvenWhenNewer() async {
        var forbidden: [String] = []
        let store = FinancialObjectStore(
            onForbiddenTransition: { _, reason in forbidden.append(reason) }
        )

        await store.apply(
            FinancialCardPayloadFixture.make(status: .completed, verification: .verified, version: 5)
        )

        // Révision strictement plus récente, mais transition impossible.
        let applied = await store.apply(
            FinancialCardPayloadFixture.make(status: .processing, verification: .verified, version: 9)
        )

        XCTAssertFalse(applied, "une transition interdite ne s'écrit pas, même plus récente")

        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.status, .completed, "l'état courant est conservé")
        XCTAssertEqual(current?.reference.version, 5)

        let count = await store.forbiddenTransitionCount
        XCTAssertEqual(count, 1)

        // Le compteur de péremption ne doit pas bouger : il signale un désordre
        // de transport, pas une transition impossible.
        let stale = await store.rejectedStaleCount
        XCTAssertEqual(stale, 0, "les deux compteurs mesurent des causes différentes")
    }

    /// Une transition licite passe toujours — la machine ne doit pas devenir un
    /// frein sur le chemin nominal.
    func test_storeStillAcceptsLawfulTransition() async {
        let store = FinancialObjectStore()
        await store.apply(
            FinancialCardPayloadFixture.make(status: .processing, verification: .unverified, version: 1)
        )
        let applied = await store.apply(
            FinancialCardPayloadFixture.make(status: .completed, verification: .verified, version: 2)
        )
        XCTAssertTrue(applied)
        let count = await store.forbiddenTransitionCount
        XCTAssertEqual(count, 0)
    }
}
