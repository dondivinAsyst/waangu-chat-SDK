//
//  Bloc1ServerReadTests.swift
//  FeatureChatTests
//
//  Lecture serveur et garde de révision — lot 1 du plan de travail restant.
//
//  Les scénarios sont ceux que le plan énumère comme critères d'acceptation :
//  requête v8 → réponse v9 ; réponses v10 puis v9 ; identité de réponse
//  incorrecte ; revalidation à révision égale.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class Bloc1ServerReadTests: XCTestCase {

    // MARK: - Montage

    private func makeUseCases(
        client: MockFinanceAPIClient,
        store: FinancialObjectStore,
        guardian: (any PaymentConfirmationGuardProtocol)? = nil
    ) -> FinancialObjectUseCases {
        FinancialObjectUseCases(
            store: store,
            client: client,
            guardian: guardian,
            capabilities: MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities),
            logger: SilentLogger()
        )
    }

    /// Garde qui accepte tout. Sert à observer le passage de `unverified` à
    /// `verified` sans dépendre d'une vraie clé.
    private struct AcceptingGuard: PaymentConfirmationGuardProtocol {
        func decide(on confirmation: PaymentConfirmation) async -> PaymentConfirmationDecision {
            .accepted
        }
    }

    // MARK: - 1.1 — la révision vient de la réponse

    /// Le scénario que le plan désigne comme première tâche d'implémentation.
    func test_refreshAdoptsServerRevisionNotRequested() async {
        let client = MockFinanceAPIClient()
        await client.setObjectResult(.success(
            FinanceFixtures.envelope(status: .processing, version: "9")
        ))

        let store = FinancialObjectStore()
        let useCases = makeUseCases(client: client, store: store)

        // La requête porte v8 ; le serveur répond v9.
        let result = await useCases.refresh(FinanceFixtures.reference(version: 8))

        guard case .success(let payload) = result else {
            return XCTFail("la lecture doit réussir")
        }
        XCTAssertEqual(payload.reference.version, 9,
                       "la révision affichée doit être celle du serveur, pas celle de la requête")

        let stored = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(stored?.reference.version, 9)
    }

    /// Une réponse portant un autre objet ne doit jamais s'appliquer sous
    /// l'identité demandée : ce serait afficher le paiement d'autrui.
    func test_refreshRejectsMismatchedIdentity() async {
        let client = MockFinanceAPIClient()
        await client.setObjectResult(.success(
            FinanceFixtures.envelope(id: "autre-objet", status: .confirmed, version: "9")
        ))

        let store = FinancialObjectStore()
        let useCases = makeUseCases(client: client, store: store)

        let result = await useCases.refresh(FinanceFixtures.reference(id: "obj-1", version: 8))

        guard case .failure = result else {
            return XCTFail("une réponse d'identité différente doit être refusée")
        }
        let stored = await store.current(for: FinanceFixtures.reference(id: "obj-1", version: 0))
        XCTAssertNil(stored, "rien ne doit être écrit sous l'identité demandée")
    }

    /// Sans révision exploitable, le client n'en invente pas.
    func test_refreshWithoutUsableRevisionInventsNothing() async {
        let client = MockFinanceAPIClient()
        await client.setObjectResult(.success(
            FinanceFixtures.envelope(status: .processing, version: "n/a")
        ))

        let store = FinancialObjectStore()
        let useCases = makeUseCases(client: client, store: store)

        _ = await useCases.refresh(FinanceFixtures.reference(version: 8))

        let stored = await store.current(for: FinanceFixtures.reference(version: 0))
        // Ni v9 fabriquée, ni révision arbitraire : celle de la requête, faute de mieux.
        XCTAssertEqual(stored?.reference.version, 8)
    }

    // MARK: - 1.2 — l'état rendu est celui qui a été retenu

    /// Le défaut central du lot 1 : une réponse refusée par le magasin était
    /// tout de même rendue à l'appelant, qui affichait la plus ancienne.
    func test_refreshReturnsRetainedStateWhenResponseIsStale() async {
        let store = FinancialObjectStore()

        // v10 déjà connue.
        let newer = FinancialCardPayloadFixture.make(
            status: .completed, verification: .verified, version: 10
        )
        let acceptedNewer = await store.apply(newer)
        XCTAssertTrue(acceptedNewer)

        // Le serveur répond v9 — arrivée tardive d'une révision dépassée.
        let client = MockFinanceAPIClient()
        await client.setObjectResult(.success(
            FinanceFixtures.envelope(status: .processing, version: "9")
        ))
        let useCases = makeUseCases(client: client, store: store)

        let result = await useCases.refresh(FinanceFixtures.reference(version: 8))

        guard case .success(let payload) = result else {
            return XCTFail("l'état retenu doit être rendu")
        }
        XCTAssertEqual(payload.reference.version, 10,
                       "la v10 retenue doit être rendue, jamais la v9 refusée")
        XCTAssertEqual(payload.status, .completed)

        let stored = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(stored?.reference.version, 10, "le magasin conserve la plus récente")
    }

    /// Deux réponses concurrentes : la plus récente survit quel que soit
    /// l'ordre d'arrivée.
    func test_concurrentResponsesKeepHighestRevision() async {
        let store = FinancialObjectStore()
        let client = MockFinanceAPIClient()
        let useCases = makeUseCases(client: client, store: store)

        await client.setObjectResult(.success(
            FinanceFixtures.envelope(status: .completed, version: "10")
        ))
        _ = await useCases.refresh(FinanceFixtures.reference(version: 8))

        await client.setObjectResult(.success(
            FinanceFixtures.envelope(status: .processing, version: "9")
        ))
        _ = await useCases.refresh(FinanceFixtures.reference(version: 8))

        let stored = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(stored?.reference.version, 10)
        XCTAssertEqual(stored?.status, .completed)
    }

    // MARK: - 1.3 — revalidation à révision égale

    /// Une clé installée après coup doit pouvoir lever l'incertitude sans
    /// qu'une nouvelle révision métier soit inventée.
    func test_refreshRevalidatesAtEqualRevision() async {
        let store = FinancialObjectStore()

        // État courant : confirmé mais non vérifié, faute de clé.
        let unverified = FinancialCardPayloadFixture.make(
            status: .confirmed, verification: .unverified, version: 5
        )
        _ = await store.apply(unverified)

        // Le serveur renvoie la même révision ; la clé est désormais installée.
        let client = MockFinanceAPIClient()
        await client.setObjectResult(.success(
            FinanceFixtures.envelope(status: .confirmed, version: "5")
        ))
        let useCases = makeUseCases(client: client, store: store, guardian: AcceptingGuard())

        let result = await useCases.refresh(FinanceFixtures.reference(version: 5))

        guard case .success(let payload) = result else {
            return XCTFail("une revalidation doit aboutir")
        }
        XCTAssertEqual(payload.verification, .verified)
        XCTAssertEqual(payload.reference.version, 5, "aucune révision métier inventée")

        let stored = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(stored?.verification, .verified)
    }

    /// Une revalidation ne peut pas servir à faire passer une contradiction :
    /// à révision égale, seul le verdict de vérification a le droit de bouger.
    func test_revalidationRefusesContradictoryPayload() async {
        let store = FinancialObjectStore()
        let existing = FinancialCardPayloadFixture.make(
            status: .confirmed, verification: .unverified, version: 5
        )
        _ = await store.apply(existing)

        // Même révision, mais statut différent — deux vérités incompatibles.
        let contradictory = FinancialCardPayloadFixture.make(
            status: .failed, verification: .verified, version: 5
        )
        let accepted = await store.revalidate(contradictory)

        XCTAssertFalse(accepted, "un statut divergent à révision égale n'est pas une revalidation")
        let stored = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(stored?.status, .confirmed, "l'état courant est conservé")
    }

    /// Une revalidation qui n'apporte rien ne notifie pas : les effets de bord
    /// attachés au changement ne doivent pas se relancer.
    func test_revalidationWithoutChangeIsRefused() async {
        let store = FinancialObjectStore()
        let existing = FinancialCardPayloadFixture.make(
            status: .confirmed, verification: .verified, version: 5
        )
        _ = await store.apply(existing)

        let identical = FinancialCardPayloadFixture.make(
            status: .confirmed, verification: .verified, version: 5
        )
        let accepted = await store.revalidate(identical)

        XCTAssertFalse(accepted)
    }
}
