//
//  PaymentIntentUseCasesTests.swift
//  FeatureChatTests
//
//  Tâches 5.5 et 5.6 — le pipeline d'émission.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class PaymentIntentUseCasesTests: XCTestCase {

    private func makeUseCases(
        client: MockFinanceAPIClient,
        preserver: MockIdempotencyPreserver = MockIdempotencyPreserver(),
        capabilities: FinanceCapabilities = FinanceIntentFixtures.openCapabilities,
        risk: StepUpLevel = .none,
        store: FinancialObjectStore = FinancialObjectStore()
    ) -> PaymentIntentUseCases {
        PaymentIntentUseCases(
            client: client,
            capabilities: MockFinanceCapabilityProvider(capabilities),
            preserver: preserver,
            riskEvaluator: MockSessionRiskEvaluator(requiredStepUp: risk),
            store: store,
            deviceID: "device-1",
            logger: SilentLogger()
        )
    }

    private func request(amount: Decimal = 5000) -> CreatePaymentIntentRequest {
        CreatePaymentIntentRequest(
            type: .payment,
            amount: amount,
            currency: "BIF",
            recipientID: "recipient-1",
            conversationID: "conv-1"
        )
    }

    // MARK: - Capacité

    /// Capacité fermée : aucune requête ne part.
    func test_closedCapabilityNeverReachesNetwork() async {
        let client = MockFinanceAPIClient()
        let useCases = makeUseCases(client: client, capabilities: .none)

        let result = await useCases.prepare(request(), operationID: "op-1")

        guard case .failure(let error) = result else { return XCTFail("doit refuser") }
        XCTAssertEqual(error, .capabilityUnavailable)
        let calls = await client.callCount
        XCTAssertEqual(calls, 0)
    }

    // MARK: - Idempotence

    /// La clé de la préparation est celle de la confirmation.
    func test_confirmReusesPreparationKey() async throws {
        let client = MockFinanceAPIClient()
        await client.setCreateResult(.success(FinanceFixtures.envelope(status: .pending)))
        await client.setConfirmResult(.success(FinanceFixtures.envelope(status: .confirmed)))

        let useCases = makeUseCases(client: client)
        guard case .success(let prepared) = await useCases.prepare(request(), operationID: "op-1")
        else { return XCTFail("préparation échouée") }

        _ = await useCases.confirm(prepared, attestation: Self.attestation(.biometric))

        let calls = await client.calls
        let keys = Set(calls.compactMap(\.idempotencyKey))
        XCTAssertEqual(keys.count, 1, "création et confirmation doivent partager une seule clé")
        XCTAssertEqual(prepared.idempotency.key, keys.first)
    }

    /// Une seconde préparation de la même opération réutilise la clé enregistrée
    /// au lieu d'en frapper une neuve — c'est ce qui couvre le kill d'application.
    func test_repreparationReusesStoredKey() async {
        let client = MockFinanceAPIClient()
        await client.setCreateResult(.success(FinanceFixtures.envelope(status: .pending)))
        let preserver = MockIdempotencyPreserver()
        let useCases = makeUseCases(client: client, preserver: preserver)

        guard case .success(let first) = await useCases.prepare(request(), operationID: "op-1"),
              case .success(let second) = await useCases.prepare(request(), operationID: "op-1")
        else { return XCTFail("préparations échouées") }

        XCTAssertEqual(first.idempotency.key, second.idempotency.key)
    }

    // MARK: - Step-up

    /// Le risque local élève l'exigence, et une attestation insuffisante est
    /// refusée **avant** le réseau.
    func test_insufficientStepUpIsRefusedBeforeNetwork() async {
        let client = MockFinanceAPIClient()
        await client.setCreateResult(.success(FinanceFixtures.envelope(status: .pending)))

        let useCases = makeUseCases(client: client, risk: .biometricAndOTP)
        guard case .success(let prepared) = await useCases.prepare(request(), operationID: "op-1")
        else { return XCTFail("préparation échouée") }

        XCTAssertEqual(prepared.requiredStepUp, .biometricAndOTP)

        let before = await client.callCount
        let result = await useCases.confirm(prepared, attestation: Self.attestation(.biometric))

        guard case .failure(let error) = result else { return XCTFail("doit refuser") }
        XCTAssertEqual(error, .forbidden)
        let after = await client.callCount
        XCTAssertEqual(after, before, "aucun appel réseau ne doit partir")
    }

    /// Une attestation absente sur une opération qui en exige une est refusée.
    func test_missingAttestationIsRefused() async {
        let client = MockFinanceAPIClient()
        await client.setCreateResult(.success(FinanceFixtures.envelope(status: .pending)))
        let useCases = makeUseCases(client: client, risk: .biometric)

        guard case .success(let prepared) = await useCases.prepare(request(), operationID: "op-1")
        else { return XCTFail("préparation échouée") }

        guard case .failure(let error) = await useCases.confirm(prepared, attestation: nil)
        else { return XCTFail("doit refuser") }
        XCTAssertEqual(error, .forbidden)
    }

    // MARK: - Expiration

    /// Un devis périmé impose un parcours complet, jamais une reprise silencieuse.
    func test_expiredQuoteIsRefused() async {
        let client = MockFinanceAPIClient()
        let useCases = makeUseCases(client: client)

        let expired = PreparedPaymentIntent(
            operationID: "op-1",
            reference: FinanceFixtures.reference(),
            card: FinancialCardPayload(
                reference: FinanceFixtures.reference(),
                status: .pending, amount: 100, currency: "BIF"
            ),
            idempotency: FinanceFixtures.idempotency(),
            requiredStepUp: .none,
            expiresAt: Date().addingTimeInterval(-1)
        )

        guard case .failure(let error) = await useCases.confirm(expired, attestation: nil)
        else { return XCTFail("doit refuser") }
        XCTAssertEqual(error, .expired)
    }

    // MARK: - Libération de clé

    /// Une opération en `unknown` **garde** sa clé : la libérer autoriserait une
    /// nouvelle tentative sous une clé neuve, donc un second débit.
    func test_unknownStatusKeepsTheKey() async {
        let client = MockFinanceAPIClient()
        await client.setCreateResult(.success(FinanceFixtures.envelope(status: .pending)))
        await client.setConfirmResult(.success(FinanceFixtures.envelope(status: .unknown)))
        let preserver = MockIdempotencyPreserver()

        let useCases = makeUseCases(client: client, preserver: preserver)
        guard case .success(let prepared) = await useCases.prepare(request(), operationID: "op-1")
        else { return XCTFail("préparation échouée") }

        // L'attestation est indispensable : le plancher backend est `.pin`, donc
        // `confirm` refuserait avant d'atteindre la libération de clé, et le test
        // passerait sans rien vérifier.
        _ = await useCases.confirm(prepared, attestation: Self.attestation(.biometric))

        let stillHeld = await preserver.context(for: "op-1")
        XCTAssertNotNil(stillHeld, "la clé doit survivre à un statut unknown")
    }

    /// Un statut final libère la clé.
    func test_terminalStatusReleasesTheKey() async {
        let client = MockFinanceAPIClient()
        await client.setCreateResult(.success(FinanceFixtures.envelope(status: .pending)))
        await client.setConfirmResult(.success(FinanceFixtures.envelope(status: .confirmed)))
        let preserver = MockIdempotencyPreserver()

        let useCases = makeUseCases(client: client, preserver: preserver)
        guard case .success(let prepared) = await useCases.prepare(request(), operationID: "op-1")
        else { return XCTFail("préparation échouée") }

        _ = await useCases.confirm(prepared, attestation: Self.attestation(.biometric))

        let released = await preserver.context(for: "op-1")
        XCTAssertNil(released)
    }

    /// Le plancher backend ne doit jamais être `.none` : le risque local serait
    /// alors seul juge, et un client compromis annoncerait « risque nul ».
    func test_stepUpFloorIsNeverNone() async {
        let client = MockFinanceAPIClient()
        await client.setCreateResult(.success(FinanceFixtures.envelope(status: .pending)))
        let useCases = makeUseCases(client: client, risk: .none)

        guard case .success(let prepared) = await useCases.prepare(request(), operationID: "op-1")
        else { return XCTFail("préparation échouée") }

        XCTAssertNotEqual(prepared.requiredStepUp, .none)
    }

    // MARK: - Helpers

    private static func attestation(_ level: StepUpLevel) -> StepUpAttestation {
        StepUpAttestation(
            level: level,
            correlationID: CorrelationId(value: "c"),
            deviceID: "device-1"
        )
    }
}

// MARK: - Demande d'argent

final class MoneyRequestUseCasesTests: XCTestCase {

    /// Le point dur de 5.6 : accepter, c'est payer. Aucun chemin ne doit permettre
    /// à un tap de débiter sans récapitulatif ni confirmation explicite.
    func test_acceptIsRefusedOnTheNonMonetaryPath() async {
        let client = MockFinanceAPIClient()
        let store = FinancialObjectStore()
        let useCases = MoneyRequestUseCases(
            client: client,
            capabilities: MockFinanceCapabilityProvider(FinanceIntentFixtures.openCapabilities),
            objects: FinancialObjectUseCases(
                store: store, client: client, guardian: nil,
                capabilities: MockFinanceCapabilityProvider(FinanceIntentFixtures.openCapabilities),
                logger: SilentLogger()
            ),
            logger: SilentLogger()
        )

        let result = await useCases.respond(
            .accept,
            to: FinanceFixtures.reference(type: .moneyRequest),
            operationID: "op-1"
        )

        guard case .failure(let error) = result else { return XCTFail("accept doit être refusé ici") }
        XCTAssertEqual(error, .capabilityUnavailable)
        let calls = await client.callCount
        XCTAssertEqual(calls, 0)
    }

    /// La classification des effets doit rester explicite pour chaque réponse.
    func test_onlyAcceptHasMonetaryEffect() {
        let monetary = MoneyRequestResponse.allCases.filter(\.hasMonetaryEffect)
        XCTAssertEqual(monetary, [.accept])
    }

    /// Seule l'annulation de sa propre demande est différable hors ligne.
    func test_onlyCancelIsQueueable() {
        let queueable = MoneyRequestResponse.allCases.filter(\.isQueueableOffline)
        XCTAssertEqual(queueable, [.cancel])
    }
}

// MARK: - Fixtures

enum FinanceIntentFixtures {
    static let openCapabilities = FinanceCapabilities(
        sendMoney: true,
        requestMoney: true,
        viewFinancialCards: true,
        context: FinanceFixtures.testContext
    )
}
