//
//  Bloc8InFlightSubmissionTests.swift
//  FeatureChatTests
//
//  Une opération tuée en vol se reprend au lancement suivant — Bloc 8 §4.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Prouve la chaîne entière qui protège d'un second débit après un kill :
/// clé enregistrée → inscription avant exécution → persistance → conservée à la
/// connexion → relue au lancement → résolue par le serveur.
///
/// Chaque maillon manquait. Un seul manquant suffit à ce que l'utilisateur,
/// relançant l'application, refasse un envoi que le serveur a peut-être déjà
/// exécuté.
final class InFlightSubmissionTests: XCTestCase {

    // MARK: - Clé enregistrée

    /// **Défaut d'origine.** L'écran passait comme identifiant d'opération une
    /// clé que le registre ne connaissait pas. Le registre réel refuse toute
    /// opération inconnue : la confirmation s'arrêtait sur `.duplicate`, avant
    /// toute exécution.
    func test_unregisteredKeyAsOperationID_isRefusedByStrictRegistry() async {
        let registry = MockIdempotencyPreserver()
        let client = MockFinanceAPIClient()
        let key = IdempotencyContext.new(deviceID: "d")

        let outcome = await makeUseCase(client: client, registry: registry).confirm(
            agreed: quote(), recipientID: "r",
            operationID: key.key, idempotency: key, attestation: nil
        )

        XCTAssertEqual(outcome, .failed(.duplicate),
                       "Fige le défaut : c'est ce que produisait l'ancien câblage des écrans")
        let confirms = await client.callCount(for: "confirm")
        XCTAssertEqual(confirms, 0)
    }

    func test_transferSubmission_executesUnderStrictRegistry() async {
        let registry = MockIdempotencyPreserver()
        let client = MockFinanceAPIClient()
        await client.setConfirmResult(.success(FinanceFixtures.envelope(id: "tx-1", status: .processing)))

        let outcome = await TransferSubmission.confirm(
            quote(), recipientID: "r", counterpartyName: "Yohana", attestation: nil,
            sendMoney: makeUseCase(client: client, registry: registry),
            operationKeys: FinanceOperationKeys(preserver: registry),
            objects: nil, deviceID: "d"
        )

        guard case .executed = outcome else {
            return XCTFail("La clé enregistrée doit passer le registre strict : \(outcome)")
        }
        let confirms = await client.callCount(for: "confirm")
        XCTAssertEqual(confirms, 1)
    }

    /// Même devis, deux tentatives : une seule clé. Sans quoi un délai dépassé
    /// suivi d'un nouvel essai exécuterait deux fois.
    func test_retryOfSameQuote_carriesTheSameKey() async {
        let registry = MockIdempotencyPreserver()
        let client = MockFinanceAPIClient()
        await client.setConfirmResult(.failure(.timeoutUnknown))
        let keys = FinanceOperationKeys(preserver: registry)
        let useCase = makeUseCase(client: client, registry: registry)

        for _ in 0..<2 {
            _ = await TransferSubmission.confirm(
                quote(), recipientID: "r", counterpartyName: nil, attestation: nil,
                sendMoney: useCase, operationKeys: keys, objects: nil, deviceID: "d"
            )
        }

        let sentKeys = await client.calls.filter { $0.operation == "confirm" }.map(\.idempotencyKey)
        XCTAssertEqual(sentKeys.count, 2)
        XCTAssertEqual(Set(sentKeys).count, 1, "Un nouvel essai n'est jamais une nouvelle opération")
    }

    // MARK: - Inscription avant exécution

    /// L'inscription doit être **sur disque** au moment où l'appel part : c'est
    /// l'instant où un kill ne laisserait rien d'autre.
    func test_submissionIsPersistedBeforeTheExecutingCall() async {
        let persistence = RecordingPersistence()
        let store = FinancialObjectStore(persistence: persistence)
        let client = SnapshottingClient(persistence: persistence)
        let objects = makeObjects(store: store, client: MockFinanceAPIClient())
        // Un seul registre, partagé comme dans l'application : la clé enregistrée
        // par `FinanceOperationKeys` est celle que le cas d'usage vérifie.
        let registry = MockIdempotencyPreserver()

        _ = await TransferSubmission.confirm(
            quote(), recipientID: "r", counterpartyName: "Yohana", attestation: nil,
            sendMoney: makeUseCase(client: client, registry: registry),
            operationKeys: FinanceOperationKeys(preserver: registry),
            objects: objects, deviceID: "d"
        )

        let seen = await client.persistedAtExecution
        XCTAssertEqual(seen?.map(\.id), ["tx-1"], "Rien n'était inscrit quand l'argent a pu partir")
        XCTAssertEqual(seen?.first?.status, PaymentStatus.unknown.rawValue)
    }

    /// Un devis refusé avant exécution ne laisse **aucune** trace : une carte
    /// « vérification en cours » pour un envoi jamais tenté serait fausse.
    func test_failureBeforeExecution_recordsNothing() async {
        let persistence = RecordingPersistence()
        let store = FinancialObjectStore(persistence: persistence)

        let outcome = await TransferSubmission.confirm(
            quote(expiresIn: -1), recipientID: "r", counterpartyName: nil, attestation: nil,
            sendMoney: makeUseCase(client: MockFinanceAPIClient(), registry: MockIdempotencyPreserver()),
            operationKeys: FinanceOperationKeys(preserver: MockIdempotencyPreserver()),
            objects: makeObjects(store: store, client: MockFinanceAPIClient()), deviceID: "d"
        )

        XCTAssertEqual(outcome, .failed(.expired))
        let saved = await persistence.load()
        XCTAssertTrue(saved.isEmpty)
    }

    // MARK: - Lancement suivant

    /// Le scénario complet : tué pendant l'appel, relancé, résolu.
    func test_operationKilledInFlight_isRestoredAndResolvedAtNextLaunch() async {
        let persistence = RecordingPersistence()

        // Lancement 1 — l'appel ne revient jamais (kill simulé par un délai
        // dépassé, sans aucune relecture possible).
        do {
            let store = FinancialObjectStore(persistence: persistence)
            let unreachable = MockFinanceAPIClient()
            await unreachable.setConfirmResult(.failure(.timeoutUnknown))
            let registry = MockIdempotencyPreserver()
            _ = await TransferSubmission.confirm(
                quote(), recipientID: "r", counterpartyName: "Yohana", attestation: nil,
                sendMoney: makeUseCase(client: unreachable, registry: registry),
                operationKeys: FinanceOperationKeys(preserver: registry),
                objects: makeObjects(store: store, client: unreachable), deviceID: "d"
            )
        }

        // Lancement 2 — magasin neuf, même disque. La connexion restaurée purge
        // la mémoire sans effacer le disque, puis relit et requête.
        let store = FinancialObjectStore(persistence: persistence)
        let server = MockFinanceAPIClient()
        await server.setObjectResult(.success(
            FinanceFixtures.envelope(id: "tx-1", status: .completed, version: "2")
        ))
        await store.clear(erasingPersistence: false)
        await store.hydrate()

        let restored = await store.hydratedReferences.map(\.id)
        XCTAssertEqual(restored, ["tx-1"], "L'opération tuée en vol doit être relue du disque")

        await makeObjects(store: store, client: server).restoreHydrated()

        let resolved = await store.current(for: FinanceFixtures.reference(id: "tx-1"))
        XCTAssertEqual(resolved?.status, .completed, "Le serveur tranche : l'envoi est passé")
        let remaining = await store.hydratedReferences
        XCTAssertTrue(remaining.isEmpty, "Une identité résolue ne se restaure plus")
    }

    /// La connexion part à chaque lancement sur session restaurée. Elle effaçait
    /// le disque — donc l'opération à reprendre — avant toute relecture.
    func test_sessionRestore_keepsPersistedSubmissions_logoutErasesThem() async {
        let persistence = RecordingPersistence()
        let store = FinancialObjectStore(persistence: persistence)
        let objects = makeObjects(store: store, client: MockFinanceAPIClient())
        await objects.recordSubmission(ambiguous(id: "tx-1"))

        await store.clear(erasingPersistence: false)
        let afterLogin = await persistence.load()
        XCTAssertEqual(afterLogin.count, 1)

        await objects.purge()
        // `clear()` efface le disque dans une tâche détachée.
        for _ in 0..<50 where await persistence.load().isEmpty == false {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        let afterLogout = await persistence.load()
        XCTAssertTrue(afterLogout.isEmpty, "La déconnexion, elle, ne laisse rien au compte suivant")
    }

    func test_terminalObjectsAreNotRestored() async {
        let persistence = RecordingPersistence(seed: [
            stored(id: "done", status: .completed),
            stored(id: "in-flight", status: .unknown),
        ])
        let store = FinancialObjectStore(persistence: persistence)

        await store.hydrate()

        let restored = await store.hydratedReferences.map(\.id)
        XCTAssertEqual(restored, ["in-flight"], "Un état final ne se requête pas à chaque lancement")
    }

    /// L'inscription ne porte pas de révision serveur : la première vérité
    /// backend doit la remplacer même à révision égale, sans quoi l'objet
    /// resterait « inconnu » pour toujours.
    func test_backendTruthReplacesRecordedSubmission_atEqualRevision() async {
        let store = FinancialObjectStore(persistence: RecordingPersistence())
        let objects = makeObjects(store: store, client: MockFinanceAPIClient())
        await objects.recordSubmission(ambiguous(id: "tx-1", version: 1))

        let accepted = await store.apply(FinancialCardPayload(
            reference: FinanceFixtures.reference(id: "tx-1", version: 1),
            status: .completed, amount: 25_375, currency: "BIF",
            counterpartyName: "Yohana", verification: .verified
        ))

        XCTAssertTrue(accepted)
        let current = await store.current(for: FinanceFixtures.reference(id: "tx-1"))
        XCTAssertEqual(current?.status, .completed)
    }

    /// Relancé sans réseau : la restauration échoue. La passe suivante du
    /// planificateur doit la retenter, et non attendre le prochain lancement.
    func test_schedulerRetriesRestorationLeftUnresolvedByOfflineLaunch() async {
        let persistence = RecordingPersistence(seed: [stored(id: "tx-1", status: .unknown)])
        let store = FinancialObjectStore(persistence: persistence)
        let server = MockFinanceAPIClient()
        await server.setObjectResult(.success(
            FinanceFixtures.envelope(id: "tx-1", status: .completed, version: "2")
        ))
        await store.hydrate()

        let scheduler = FinancialReconciliationScheduler(
            useCases: makeObjects(store: store, client: server), logger: SilentLogger()
        )
        await scheduler.networkDidBecomeAvailable()

        // Au moins une lecture : sans garde de confirmation, la charge relue reste
        // « non vérifiée » et la même passe la reprend une seconde fois.
        let refreshes = await server.callCount(for: "refresh")
        XCTAssertGreaterThanOrEqual(refreshes, 1)
        let resolved = await store.current(for: FinanceFixtures.reference(id: "tx-1"))
        XCTAssertEqual(resolved?.status, .completed)
    }

    // MARK: - Fabriques

    private func quote(expiresIn: TimeInterval = 120) -> TransferQuote {
        TransferQuote(
            reference: FinanceFixtures.reference(id: "tx-1", version: 1),
            amount: 25_000, currency: "BIF",
            feeAmount: 375, feeCurrency: "BIF",
            totalAmount: 25_375, totalCurrency: "BIF",
            recipientVerification: .verified,
            complianceState: .approved,
            issuedAt: Date(),
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    private func makeUseCase(client: any FinanceAPIClientProtocol,
                             registry: any IdempotencyKeyPreserving) -> SendMoneyUseCase {
        SendMoneyUseCase(quoting: UnchangedQuoting(), permits: AlwaysPermits(),
                         client: client, preserver: registry, logger: SilentLogger())
    }

    private func makeObjects(store: FinancialObjectStore,
                             client: any FinanceAPIClientProtocol) -> FinancialObjectUseCases {
        FinancialObjectUseCases(
            store: store, client: client, guardian: nil,
            capabilities: MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities),
            logger: SilentLogger()
        )
    }

    private func ambiguous(id: String, version: Int = 1) -> FinancialCardPayload {
        FinancialOutcomeRoute.ambiguousPayload(
            reference: FinanceFixtures.reference(id: id, version: version),
            amount: 25_375, currency: "BIF", counterpartyName: "Yohana"
        )
    }

    private func stored(id: String, status: PaymentStatus) -> PersistedFinancialObject {
        PersistedFinancialObject(type: FinancialObjectType.payment.rawValue, id: id,
                                 version: 1, status: status.rawValue, lastKnownAt: Date())
    }
}

// MARK: - Doublures

private actor RecordingPersistence: FinancialObjectPersisting {
    private var stored: [String: PersistedFinancialObject] = [:]

    init(seed: [PersistedFinancialObject] = []) {
        stored = Dictionary(uniqueKeysWithValues: seed.map { ($0.identityKey, $0) })
    }

    func load() async -> [PersistedFinancialObject] {
        stored.values.sorted { $0.id < $1.id }
    }
    func save(_ object: PersistedFinancialObject) async { stored[object.identityKey] = object }
    func remove(type: String, id: String) async {
        stored[PersistedFinancialObject.identityKey(type: type, id: id)] = nil
    }
    func clear() async { stored.removeAll() }
}

/// Relève ce que le disque contient à l'instant où l'exécution part, puis ne
/// répond jamais utilement — l'équivalent d'un kill vu du client.
private actor SnapshottingClient: FinanceAPIClientProtocol {
    private let persistence: RecordingPersistence
    private(set) var persistedAtExecution: [PersistedFinancialObject]?

    init(persistence: RecordingPersistence) { self.persistence = persistence }

    func capabilities() async throws -> FinanceCapabilities { .none }
    func financialObject(for reference: FinancialReference) async throws -> PaymentEnvelope {
        throw FinanceError.timeoutUnknown
    }
    func refresh(_ reference: FinancialReference) async throws -> PaymentEnvelope {
        throw FinanceError.timeoutUnknown
    }
    func createPaymentIntent(_ request: CreatePaymentIntentRequest,
                             idempotency: IdempotencyContext) async throws -> PaymentEnvelope {
        throw FinanceError.timeoutUnknown
    }
    func confirmPaymentIntent(reference: FinancialReference, idempotency: IdempotencyContext,
                              stepUp: StepUpAttestation?) async throws -> PaymentEnvelope {
        persistedAtExecution = await persistence.load()
        throw FinanceError.timeoutUnknown
    }
}

private struct UnchangedQuoting: TransferQuoting {
    func quote(for draft: TransferDraft) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    func refreshQuote(_ quote: TransferQuote) async -> Result<TransferQuote, FinanceError> {
        .success(quote)
    }
}

private struct AlwaysPermits: ExecutionPermitIssuing {
    func issue(for snapshot: ConfirmationSnapshot, idempotency: IdempotencyContext,
               stepUp: StepUpAttestation?) async -> Result<ExecutionPermit, FinanceError> {
        .success(ExecutionPermit(
            permitID: "p-1", objectID: snapshot.reference.id,
            snapshotHash: snapshot.decisionHash,
            issuedAt: Date(), expiresAt: Date().addingTimeInterval(180)
        ))
    }
    func consume(_ permit: ExecutionPermit) async -> Result<Void, FinanceError> { .success(()) }
}
