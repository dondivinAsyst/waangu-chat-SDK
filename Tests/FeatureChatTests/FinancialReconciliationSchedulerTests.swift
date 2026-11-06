//
//  FinancialReconciliationSchedulerTests.swift
//  FeatureChatTests
//
//  Les déclencheurs de réconciliation, et le délai de grâce qu'ils respectent.
//
//  Le planificateur exposait quatre points d'entrée dont un seul était appelé,
//  et son délai de grâce n'était consulté nulle part. Ces tests décrivent le
//  comportement que le câblage doit produire.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinancialReconciliationSchedulerTests: XCTestCase {

    private func makeStack(
        grace: TimeInterval = 120
    ) async -> (FinancialReconciliationScheduler, FinancialObjectStore, MockFinanceAPIClient) {
        let client = MockFinanceAPIClient()
        await client.setObjectResult(.success(FinanceFixtures.envelope(status: .unknown)))

        let store = FinancialObjectStore()
        let useCases = FinancialObjectUseCases(
            store: store,
            client: client,
            guardian: nil,
            capabilities: MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities),
            logger: SilentLogger()
        )
        let scheduler = FinancialReconciliationScheduler(
            useCases: useCases,
            logger: SilentLogger(),
            ambiguityGracePeriod: grace
        )
        return (scheduler, store, client)
    }

    private func ambiguous(age: TimeInterval) -> FinancialCardPayload {
        FinancialCardPayloadFixture.make(
            status: .unknown,
            verification: .unverified,
            lastRefreshedAt: Date().addingTimeInterval(-age)
        )
    }

    // MARK: - Délai de grâce

    /// Un objet qui vient de basculer en `unknown` a peut-être une réponse
    /// serveur en vol. Le requêter aussitôt double la charge sans rien apprendre.
    func test_periodicSweepSkipsObjectsInsideGracePeriod() async {
        let (scheduler, store, client) = await makeStack()
        await store.apply(ambiguous(age: 5))

        await scheduler.periodicSweep()

        let refreshes = await client.callCount(for: "refresh")
        XCTAssertEqual(refreshes, 0)
        let runs = await scheduler.runCount
        XCTAssertEqual(runs, 0, "une passe vide ne doit pas être comptée")
    }

    /// Passé le délai, plus personne d'autre ne reprendra cet objet.
    func test_periodicSweepPicksUpAgedAmbiguity() async {
        let (scheduler, store, client) = await makeStack()
        await store.apply(ambiguous(age: 300))

        await scheduler.periodicSweep()

        let refreshes = await client.callCount(for: "refresh")
        XCTAssertEqual(refreshes, 1)
    }

    /// Le retour du réseau reprend tout : l'état affiché date d'avant la coupure,
    /// quelle que soit son ancienneté.
    func test_networkReturnForcesEvenFreshObjects() async {
        let (scheduler, store, client) = await makeStack()
        await store.apply(ambiguous(age: 1))

        await scheduler.networkDidBecomeAvailable()

        let refreshes = await client.callCount(for: "refresh")
        XCTAssertEqual(refreshes, 1, "le retour du réseau ignore le délai de grâce")
    }

    // MARK: - Intervalle minimal

    /// Un objet qui reste ambigu ne doit pas produire une requête par tick :
    /// un incident backend deviendrait une tempête venue de tous les clients.
    func test_secondSweepIsThrottled() async {
        let (scheduler, store, client) = await makeStack()
        await store.apply(ambiguous(age: 300))

        await scheduler.periodicSweep()
        await scheduler.periodicSweep()

        let refreshes = await client.callCount(for: "refresh")
        XCTAssertEqual(refreshes, 1)
    }

    /// `reset()` déclare que l'état précédent ne s'applique plus — y compris
    /// l'horodatage qui étouffe la passe suivante.
    ///
    /// Délai de grâce nul : la relecture identique réarme désormais ce délai,
    /// et ce test ne porte que sur l'intervalle minimal.
    func test_resetReleasesTheThrottle() async {
        let (scheduler, store, client) = await makeStack(grace: 0)
        await store.apply(ambiguous(age: 300))

        await scheduler.periodicSweep()
        await scheduler.reset()
        await scheduler.periodicSweep()

        let refreshes = await client.callCount(for: "refresh")
        XCTAssertEqual(refreshes, 2)
    }

    /// Rien à reprendre : la passe ne doit pas s'horodater, sinon elle ferait
    /// taire la passe suivante, qui aurait peut-être quelque chose à faire.
    func test_emptySweepDoesNotConsumeTheInterval() async {
        let (scheduler, store, client) = await makeStack()

        await scheduler.periodicSweep()          // magasin vide
        await store.apply(ambiguous(age: 300))
        await scheduler.periodicSweep()          // doit s'exécuter malgré tout

        let refreshes = await client.callCount(for: "refresh")
        XCTAssertEqual(refreshes, 1)
    }
}

// MARK: - Purge de session

final class FinancialStatePurgeTests: XCTestCase {

    /// Conserver les objets du compte précédent afficherait les paiements de
    /// quelqu'un d'autre dans les conversations du suivant.
    func test_purgeEmptiesTheStore() async {
        let store = FinancialObjectStore()
        let useCases = FinancialObjectUseCases(
            store: store,
            client: nil,
            guardian: nil,
            capabilities: MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities),
            logger: SilentLogger()
        )

        await store.apply(
            FinancialCardPayloadFixture.make(status: .confirmed, verification: .verified)
        )
        let before = await store.allObjects.count
        XCTAssertEqual(before, 1)

        await useCases.purge()

        let after = await store.allObjects.count
        XCTAssertEqual(after, 0)
        let pending = await useCases.pendingReconciliation()
        XCTAssertTrue(pending.isEmpty)
    }

    /// La purge doit aussi oublier les échos locaux, sinon la première charge
    /// backend du compte suivant serait acceptée sans contrôle de version.
    func test_purgeForgetsLocalEchoes() async {
        let store = FinancialObjectStore()
        await store.applyLocalEcho(
            FinancialCardPayloadFixture.make(status: .processing, verification: .unverified, version: 4)
        )
        await store.clear()

        let isEcho = await store.isLocalEcho(FinanceFixtures.reference(version: 0))
        XCTAssertFalse(isEcho)

        // Après purge, la garde de version reprend son rôle normal.
        await store.apply(FinancialCardPayloadFixture.make(status: .confirmed, verification: .verified, version: 9))
        let applied = await store.apply(
            FinancialCardPayloadFixture.make(status: .processing, verification: .verified, version: 2)
        )
        XCTAssertFalse(applied)
    }
}
