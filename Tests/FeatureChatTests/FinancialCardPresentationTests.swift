//
//  FinancialCardPresentationTests.swift
//  FeatureChatTests
//
//  La porte du Bloc 1 : aucun succès affiché sans vérification, et aucune
//  révision fabriquée par le client.
//
//  Ce fichier existe parce que les deux règles étaient écrites, testées au
//  niveau du prédicat, et contournées au niveau du rendu. Un prédicat vérifié
//  qu'aucune vue n'appelle ne protège rien.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

// MARK: - Fixture

enum FinancialCardPayloadFixture {

    static func make(
        status: PaymentStatus,
        verification: FinancialCardVerification,
        version: Int = 1,
        id: String = "obj-1",
        lastRefreshedAt: Date = Date()
    ) -> FinancialCardPayload {
        FinancialCardPayload(
            reference: FinanceFixtures.reference(id: id, version: version),
            status: status,
            amount: 1000,
            currency: "BIF",
            lastRefreshedAt: lastRefreshedAt,
            verification: verification
        )
    }
}

// MARK: - Le produit croisé complet

final class FinancialCardPresentationTests: XCTestCase {

    private static let verifications: [FinancialCardVerification] = [
        .verified, .unverified, .rejected
    ]

    /// **Le test qui aurait dû exister.**
    ///
    /// Balaie `PaymentStatus × FinancialCardVerification` en entier — 21 × 3 — et
    /// exige que le traitement n'annonce un succès que là où `canPresentAsSettled`
    /// l'autorise. Aucune exception, aucun statut privilégié.
    func test_successPresentationOnlyWhereVerificationAllowsIt() {
        for status in PaymentStatus.allCases {
            for verification in Self.verifications {
                let payload = FinancialCardPayloadFixture.make(
                    status: status,
                    verification: verification
                )
                XCTAssertEqual(
                    payload.presentation.announcesSuccess,
                    payload.canPresentAsSettled,
                    "\(status) / \(verification) : le traitement et la règle divergent"
                )
            }
        }
    }

    /// Le cas exact du défaut corrigé : un objet confirmé que ce client n'a pas
    /// pu vérifier. C'est l'état de **tout** objet tant que le contrat backend #1
    /// n'installe pas de clé de signature.
    func test_confirmedButUnverifiedPresentsAsVerifying() {
        for status in [PaymentStatus.confirmed, .completed] {
            let payload = FinancialCardPayloadFixture.make(
                status: status,
                verification: .unverified
            )
            XCTAssertEqual(payload.presentation, .verifying)
            XCTAssertFalse(payload.presentation.announcesSuccess)
        }
    }

    /// Une signature vérifiable et fausse l'emporte sur n'importe quel statut :
    /// le contenu n'est pas celui que le backend a signé.
    func test_rejectedVerificationAlwaysRepudiates() {
        for status in PaymentStatus.allCases {
            let payload = FinancialCardPayloadFixture.make(
                status: status,
                verification: .rejected
            )
            XCTAssertEqual(payload.presentation, .repudiated, "\(status)")
        }
    }

    /// Seul `settled` a le droit d'annoncer un succès. Un traitement ajouté plus
    /// tard sans y penser fait tomber ce test.
    func test_settledIsTheOnlySuccessTreatment() {
        let announcing = FinancialCardPresentation.allCases.filter(\.announcesSuccess)
        XCTAssertEqual(announcing, [.settled])
    }
}

// MARK: - Autorité sur la révision

final class FinancialRevisionAuthorityTests: XCTestCase {

    private func makeUseCases(
        client: MockFinanceAPIClient,
        store: FinancialObjectStore
    ) -> PaymentIntentUseCases {
        PaymentIntentUseCases(
            client: client,
            capabilities: MockFinanceCapabilityProvider(FinanceIntentFixtures.openCapabilities),
            preserver: MockIdempotencyPreserver(),
            riskEvaluator: MockSessionRiskEvaluator(requiredStepUp: .none),
            store: store,
            deviceID: "device-1",
            logger: SilentLogger()
        )
    }

    private func request() -> CreatePaymentIntentRequest {
        CreatePaymentIntentRequest(
            type: .payment,
            amount: 5000,
            currency: "BIF",
            recipientID: "recipient-1",
            conversationID: "conv-1"
        )
    }

    private static func attestation(_ level: StepUpLevel) -> StepUpAttestation {
        StepUpAttestation(
            level: level,
            correlationID: CorrelationId(value: "c"),
            deviceID: "device-1"
        )
    }

    /// La révision de la confirmation est celle du backend — jamais celle de la
    /// préparation incrémentée.
    func test_confirmAdoptsBackendRevision() async {
        let client = MockFinanceAPIClient()
        await client.setCreateResult(.success(FinanceFixtures.envelope(status: .pending, version: "1")))
        await client.setConfirmResult(.success(FinanceFixtures.envelope(status: .confirmed, version: "7")))

        let store = FinancialObjectStore()
        let useCases = makeUseCases(client: client, store: store)

        guard case .success(let prepared) = await useCases.prepare(request(), operationID: "op-1")
        else { return XCTFail("préparation échouée") }
        XCTAssertEqual(prepared.reference.version, 1)

        _ = await useCases.confirm(prepared, attestation: Self.attestation(.biometric))

        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.reference.version, 7, "la révision backend doit être adoptée telle quelle")
        let isEcho = await store.isLocalEcho(FinanceFixtures.reference(version: 0))
        XCTAssertFalse(isEcho, "une révision backend fait autorité")
    }

    /// Sans révision exploitable, le client n'en invente pas : la charge reste à
    /// la révision préparée et se déclare écho local.
    func test_confirmWithoutRevisionDoesNotInventOne() async {
        let client = MockFinanceAPIClient()
        await client.setCreateResult(.success(FinanceFixtures.envelope(status: .pending, version: "1")))
        await client.setConfirmResult(.success(FinanceFixtures.envelope(status: .confirmed, version: "n/a")))

        let store = FinancialObjectStore()
        let useCases = makeUseCases(client: client, store: store)

        guard case .success(let prepared) = await useCases.prepare(request(), operationID: "op-1")
        else { return XCTFail("préparation échouée") }

        _ = await useCases.confirm(prepared, attestation: Self.attestation(.biometric))

        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.reference.version, prepared.reference.version)
        XCTAssertEqual(current?.status, .confirmed)
        let isEcho = await store.isLocalEcho(FinanceFixtures.reference(version: 0))
        XCTAssertTrue(isEcho)
    }

    /// **La régression que le `+ 1` provoquait.**
    ///
    /// Le backend corrige `confirmed` en `failed` à sa propre révision. Sous
    /// l'ancienne arithmétique, cette correction arrivait « périmée » et était
    /// jetée : la carte restait sur le statut optimiste, définitivement.
    func test_backendCorrectionAppliesOverLocalEcho() async {
        let client = MockFinanceAPIClient()
        await client.setCreateResult(.success(FinanceFixtures.envelope(status: .pending, version: "1")))
        await client.setConfirmResult(.success(FinanceFixtures.envelope(status: .confirmed, version: "n/a")))

        let store = FinancialObjectStore()
        let useCases = makeUseCases(client: client, store: store)

        guard case .success(let prepared) = await useCases.prepare(request(), operationID: "op-1")
        else { return XCTFail("préparation échouée") }
        _ = await useCases.confirm(prepared, attestation: Self.attestation(.biometric))

        // Vérité backend à la même révision que l'écho — elle doit passer.
        let truth = FinancialCardPayloadFixture.make(
            status: .failed,
            verification: .verified,
            version: prepared.reference.version
        )
        let applied = await store.apply(truth)

        XCTAssertTrue(applied, "une vérité backend l'emporte toujours sur un écho local")
        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.status, .failed)
        XCTAssertFalse(current?.presentation.announcesSuccess ?? true)
    }

    /// Deux vérités backend restent départagées par la version, écho ou pas :
    /// la porte de l'écho ne doit pas ouvrir la voie aux événements désordonnés.
    func test_staleBackendEventStillRejectedAfterEchoResolved() async {
        let store = FinancialObjectStore()

        await store.applyLocalEcho(
            FinancialCardPayloadFixture.make(status: .processing, verification: .unverified, version: 1)
        )
        _ = await store.apply(
            FinancialCardPayloadFixture.make(status: .confirmed, verification: .verified, version: 5)
        )
        let applied = await store.apply(
            FinancialCardPayloadFixture.make(status: .processing, verification: .verified, version: 3)
        )

        XCTAssertFalse(applied, "v3 après v5 reste périmée")
        let current = await store.current(for: FinanceFixtures.reference(version: 0))
        XCTAssertEqual(current?.reference.version, 5)
    }
}
