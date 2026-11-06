//
//  FinancialObjectStoreTests.swift
//  FeatureChatTests
//
//  Tâches 10.8, 10.9 — désordre et duplication d'événements.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinancialObjectStoreTests: XCTestCase {

    private func payload(_ version: Int, status: PaymentStatus = .processing, id: String = "obj-1") -> FinancialCardPayload {
        FinancialCardPayload(
            reference: FinanceFixtures.reference(id: id, version: version),
            status: status,
            amount: 1000,
            currency: "BIF"
        )
    }

    func test_firstObjectIsAlwaysApplied() async {
        let store = FinancialObjectStore()
        let applied = await store.apply(payload(1))
        XCTAssertTrue(applied)
    }

    /// Le scénario du §3.2 : v8 arrive après v9 à la reconnexion.
    func test_v8AfterV9LeavesV9() async {
        let store = FinancialObjectStore()

        await store.apply(payload(9, status: .confirmed))
        let applied = await store.apply(payload(8, status: .processing))

        XCTAssertFalse(applied)
        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.reference.version, 9)
        XCTAssertEqual(current?.status, .confirmed)
    }

    /// Ordre v8 → v9 → v8 : l'état final doit être v9.
    func test_outOfOrderSequenceConvergesToHighest() async {
        let store = FinancialObjectStore()

        await store.apply(payload(8))
        await store.apply(payload(9, status: .confirmed))
        await store.apply(payload(8))

        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.reference.version, 9)
    }

    /// Un événement dupliqué ne doit être appliqué qu'une fois.
    func test_duplicateEventAppliedOnce() async {
        let store = FinancialObjectStore()

        let first = await store.apply(payload(3))
        let second = await store.apply(payload(3))

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let rejected = await store.rejectedStaleCount
        XCTAssertEqual(rejected, 1)
    }

    /// L'ordre d'arrivée d'un lot ne doit pas changer le résultat.
    func test_batchOrderDoesNotMatter() async {
        let ascending = FinancialObjectStore()
        let descending = FinancialObjectStore()

        await ascending.applyAll([payload(1), payload(2), payload(3)])
        await descending.applyAll([payload(3), payload(2), payload(1)])

        let a = await ascending.current(for: FinanceFixtures.reference(version: 0))
        let d = await descending.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(a?.reference.version, 3)
        XCTAssertEqual(d?.reference.version, 3)
    }

    /// Les rejets doivent être comptés : c'est le signal d'alerte du §9.4.
    func test_staleRejectionsAreCounted() async {
        let store = FinancialObjectStore()

        await store.apply(payload(5))
        await store.apply(payload(4))
        await store.apply(payload(3))

        let count = await store.rejectedStaleCount
        XCTAssertEqual(count, 2)
    }

    /// Deux objets distincts ne se marchent pas dessus, même à versions croisées.
    func test_distinctObjectsAreIndependent() async {
        let store = FinancialObjectStore()

        await store.apply(payload(10, id: "obj-a"))
        let applied = await store.apply(payload(1, id: "obj-b"))

        XCTAssertTrue(applied)
    }

    /// Au changement de compte, conserver les objets afficherait les paiements
    /// de quelqu'un d'autre.
    func test_clearEmptiesEverything() async {
        let store = FinancialObjectStore()
        await store.apply(payload(1))
        await store.clear()

        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertNil(current)
    }

    func test_pendingObjectsAreListedForReconciliation() async {
        let store = FinancialObjectStore()
        await store.apply(payload(1, status: .unknown))
        await store.apply(payload(1, status: .confirmed, id: "obj-2"))

        let pending = await store.needingReconciliation
        // `obj-1` est en `unknown` ; `obj-2` est confirmé mais non vérifié,
        // donc lui aussi doit être repris.
        XCTAssertEqual(pending.count, 2)
    }
}
