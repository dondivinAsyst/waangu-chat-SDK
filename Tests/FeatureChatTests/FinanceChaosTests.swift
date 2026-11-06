//
//  FinanceChaosTests.swift
//  FeatureChatTests
//
//  Tâches 10.6, 10.7, 10.10, 10.12, 10.13 — scénarios de chaos du §11.2.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinanceChaosTests: XCTestCase {

    private func makeUseCases(
        client: MockFinanceAPIClient,
        store: FinancialObjectStore,
        guardian: (any PaymentConfirmationGuardProtocol)? = nil,
        capabilities: FinanceCapabilities = FinanceFixtures.readOnlyCapabilities
    ) -> FinancialObjectUseCases {
        FinancialObjectUseCases(
            store: store,
            client: client,
            guardian: guardian,
            capabilities: MockFinanceCapabilityProvider(capabilities),
            logger: SilentLogger()
        )
    }

    // MARK: - Réseau coupé pendant la confirmation

    /// Un timeout après soumission ne doit produire ni `failed`, ni débit affiché.
    func test_timeoutAfterSubmissionYieldsUnknownNotFailure() async {
        let client = MockFinanceAPIClient()
        await client.setObjectResult(.failure(.timeoutUnknown))

        let useCases = makeUseCases(client: client, store: FinancialObjectStore())
        let result = await useCases.refresh(FinanceFixtures.reference())

        guard case .failure(let error) = result else {
            return XCTFail("Un timeout doit remonter une erreur")
        }
        XCTAssertEqual(error, .timeoutUnknown)
        XCTAssertEqual(error.displayedStatus, .unknown)
        XCTAssertFalse(error.isSafeToRetry)
    }

    // MARK: - Serveur qui répond après le timeout

    /// La réponse tardive du serveur fait autorité, sans créer de second objet.
    func test_lateServerResponseWinsWithoutDuplicating() async {
        let store = FinancialObjectStore()
        let client = MockFinanceAPIClient()

        // Le client a d'abord conclu à l'ambiguïté.
        await store.apply(FinancialCardPayload(
            reference: FinanceFixtures.reference(version: 1),
            status: .unknown,
            amount: 1000,
            currency: "BIF"
        ))

        // Puis le serveur répond, en version supérieure.
        //
        // La révision est portée par la **réponse**, plus par la requête : depuis
        // le §1.1 du Bloc 1 le client ignore la version demandée et n'adopte que
        // celle du serveur (voir `test_refreshAdoptsServerRevisionNotRequested`).
        // Ce test passait la v2 dans la requête et laissait le serveur répondre
        // v1 — il affirmait donc le comportement que le §1.1 a supprimé.
        await client.setObjectResult(.success(FinanceFixtures.envelope(status: .confirmed, version: "2")))
        let useCases = makeUseCases(client: client, store: store)
        _ = await useCases.refresh(FinanceFixtures.reference(version: 2))

        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.status, .confirmed)
        XCTAssertEqual(current?.reference.version, 2)

        // Un seul objet, pas deux.
        let all = await store.allObjects
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - Événement manquant

    /// Un trou dans la séquence d'événements se comble par lecture serveur.
    func test_missingEventIsFilledByRefresh() async {
        let store = FinancialObjectStore()
        let client = MockFinanceAPIClient()
        // v2 n'est jamais arrivé ; le serveur rend directement v5. Révision portée
        // par la réponse — voir la note du test précédent.
        await client.setObjectResult(.success(FinanceFixtures.envelope(status: .confirmed, version: "5")))

        await store.apply(FinancialCardPayload(
            reference: FinanceFixtures.reference(version: 1),
            status: .processing, amount: 1000, currency: "BIF"
        ))

        // La lecture ramène directement v5.
        let useCases = makeUseCases(client: client, store: store)
        _ = await useCases.refresh(FinanceFixtures.reference(version: 5))

        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.reference.version, 5)
    }

    // MARK: - Réconciliation

    /// Tout objet ambigu est repris, et un seul appel par objet est émis.
    func test_reconciliationVisitsEachPendingObjectOnce() async {
        let store = FinancialObjectStore()
        let client = MockFinanceAPIClient()
        await client.setObjectResult(.success(FinanceFixtures.envelope(status: .confirmed)))

        for id in ["a", "b", "c"] {
            await store.apply(FinancialCardPayload(
                reference: FinanceFixtures.reference(id: id, version: 1),
                status: .unknown, amount: 100, currency: "BIF"
            ))
        }

        let useCases = makeUseCases(client: client, store: store)
        await useCases.reconcilePending()

        let refreshes = await client.callCount(for: "refresh")
        XCTAssertEqual(refreshes, 3)
    }

    /// Rien à réconcilier ne doit produire aucun appel réseau.
    func test_reconciliationIsSilentWhenNothingPending() async {
        let store = FinancialObjectStore()
        let client = MockFinanceAPIClient()

        let useCases = makeUseCases(client: client, store: store)
        await useCases.reconcilePending()

        let count = await client.callCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Capacité fermée

    /// Capacité fermée : aucune requête ne doit atteindre le réseau.
    func test_closedCapabilityBlocksNetworkAccess() async {
        let client = MockFinanceAPIClient()
        let useCases = makeUseCases(
            client: client,
            store: FinancialObjectStore(),
            capabilities: .none
        )

        let result = await useCases.refresh(FinanceFixtures.reference())

        guard case .failure(let error) = result else {
            return XCTFail("Une capacité fermée doit refuser")
        }
        XCTAssertEqual(error, .capabilityUnavailable)
        let count = await client.callCount
        XCTAssertEqual(count, 0, "Aucun appel réseau ne doit partir")
    }

    // MARK: - Double tap

    /// Deux applications concurrentes de la même révision n'en retiennent qu'une.
    func test_concurrentIdenticalRevisionsAppliedOnce() async {
        let store = FinancialObjectStore()
        let payload = FinancialCardPayload(
            reference: FinanceFixtures.reference(version: 3),
            status: .confirmed, amount: 1000, currency: "BIF"
        )

        async let first = store.apply(payload)
        async let second = store.apply(payload)
        let results = await [first, second]

        XCTAssertEqual(results.filter { $0 }.count, 1, "Une seule application doit réussir")
    }
}
