//
//  Bloc1SessionRestoreTests.swift
//  FeatureChatTests
//
//  Restauration après kill et isolation des comptes — lot 2.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class Bloc1SessionRestoreTests: XCTestCase {

    /// Persistance en mémoire, pour observer ce que le magasin écrit vraiment.
    private actor SpyPersistence: FinancialObjectPersisting {
        private var stored: [String: PersistedFinancialObject] = [:]
        private(set) var clearCount = 0

        init(seed: [PersistedFinancialObject] = []) {
            stored = Dictionary(uniqueKeysWithValues: seed.map { ($0.identityKey, $0) })
        }

        func load() async -> [PersistedFinancialObject] { Array(stored.values) }
        func save(_ object: PersistedFinancialObject) async { stored[object.identityKey] = object }
        func remove(type: String, id: String) async {
            stored[PersistedFinancialObject.identityKey(type: type, id: id)] = nil
        }
        func clear() async { stored.removeAll(); clearCount += 1 }
        var count: Int { stored.count }
    }

    // MARK: - 2.1 — ce qui est retenu

    func test_appliedPayloadIsPersisted() async {
        let persistence = SpyPersistence()
        let store = FinancialObjectStore(persistence: persistence)

        _ = await store.apply(FinancialCardPayloadFixture.make(
            status: .processing, verification: .unverified, version: 3
        ))

        let saved = await persistence.load()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.version, 3)
    }

    // MARK: - 2.2 — restaurer avant de réconcilier

    /// Le défaut du lot 2.2 : une liste d'identités hydratées sans consommateur.
    func test_hydrationExposesUsableReferences() async {
        let persistence = SpyPersistence(seed: [
            PersistedFinancialObject(
                type: FinancialObjectType.payment.rawValue,
                id: "obj-restauré", version: 4,
                status: PaymentStatus.unknown.rawValue, lastKnownAt: Date()
            )
        ])
        let store = FinancialObjectStore(persistence: persistence)

        await store.hydrate()
        let references = await store.hydratedReferences

        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(references.first?.id, "obj-restauré")
        XCTAssertEqual(references.first?.version, 4)
        XCTAssertEqual(references.first?.type, .payment)
    }

    /// L'hydratation n'écrase jamais un état mémoire plus frais.
    func test_hydrationDoesNotOverwriteLiveState() async {
        let persistence = SpyPersistence(seed: [
            PersistedFinancialObject(
                type: FinancialObjectType.payment.rawValue,
                id: "obj-1", version: 2,
                status: PaymentStatus.processing.rawValue, lastKnownAt: Date()
            )
        ])
        let store = FinancialObjectStore(persistence: persistence)

        _ = await store.apply(FinancialCardPayloadFixture.make(
            status: .completed, verification: .verified, version: 9
        ))
        await store.hydrate()

        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.reference.version, 9, "la mémoire est plus fraîche que le disque")
    }

    /// Une restauration produit des lectures serveur, pas seulement une liste.
    func test_restoreHydratedIssuesServerReads() async {
        let persistence = SpyPersistence(seed: [
            PersistedFinancialObject(
                type: FinancialObjectType.payment.rawValue,
                id: "obj-1", version: 4,
                status: PaymentStatus.unknown.rawValue, lastKnownAt: Date()
            )
        ])
        let store = FinancialObjectStore(persistence: persistence)
        let client = MockFinanceAPIClient()
        await client.setObjectResult(.success(
            FinanceFixtures.envelope(status: .completed, version: "5")
        ))

        let useCases = FinancialObjectUseCases(
            store: store, client: client, guardian: nil,
            capabilities: MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities),
            logger: SilentLogger()
        )

        await store.hydrate()
        await useCases.restoreHydrated()

        let calls = await client.calls
        XCTAssertTrue(calls.contains { $0.operation == "refresh" },
                      "la restauration doit produire une lecture serveur")

        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.reference.version, 5)
    }

    // MARK: - 2.5 — isolation des comptes

    /// Une réponse du compte A reçue après connexion de B doit être jetée.
    func test_responseFromPreviousSessionIsRefused() async {
        let store = FinancialObjectStore()

        // Jeton relevé sous la session A, avant la requête.
        let sessionA = await store.currentSessionToken

        // Connexion de B pendant que la requête est en vol.
        await store.beginSession()

        let accepted = await store.apply(
            FinancialCardPayloadFixture.make(
                status: .completed, verification: .verified, version: 7
            ),
            session: sessionA
        )

        XCTAssertFalse(accepted, "une réponse de la session précédente ne s'écrit pas")
        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertNil(current, "rien du compte précédent ne doit apparaître")

        let rejected = await store.foreignSessionRejectedCount
        XCTAssertEqual(rejected, 1, "le refus doit être compté séparément du péremptoire")
    }

    /// Le jeton de la session courante laisse évidemment passer.
    func test_currentSessionResponseIsAccepted() async {
        let store = FinancialObjectStore()
        let session = await store.currentSessionToken

        let accepted = await store.apply(
            FinancialCardPayloadFixture.make(
                status: .completed, verification: .verified, version: 7
            ),
            session: session
        )
        XCTAssertTrue(accepted)
    }

    /// Ouvrir une session purge l'état précédent.
    func test_beginSessionPurgesPreviousAccount() async {
        let persistence = SpyPersistence()
        let store = FinancialObjectStore(persistence: persistence)

        _ = await store.apply(FinancialCardPayloadFixture.make(
            status: .completed, verification: .verified, version: 2
        ))
        await store.beginSession()

        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertNil(current)
        let hydrated = await store.hydratedIdentities
        XCTAssertTrue(hydrated.isEmpty)
    }

    /// Les appelants sans requête réseau (MQTT, sync) ne sont pas bloqués.
    func test_nilSessionSkipsTheCheck() async {
        let store = FinancialObjectStore()
        await store.beginSession()

        let accepted = await store.apply(
            FinancialCardPayloadFixture.make(
                status: .processing, verification: .unverified, version: 1
            ),
            session: nil
        )
        XCTAssertTrue(accepted)
    }
}
