import Testing
import Foundation
@testable import WaanguCoreKit

/// Résilience sur le chemin financier réel — §15, §17, §19.
///
/// Le décorateur enveloppe un protocole, donc ces règles se vérifient **sans
/// réseau** : le client enveloppé est un compteur d'appels.
@Suite("Bloc 6 — client financier résilient")
struct Bloc6ResilientClientTests {

    private let bif = CurrencyCode(code: "BIF", exponent: 0)

    /// Client enveloppé, entièrement pilotable.
    private actor SpyClient: FinanceAPIClientProtocol {

        enum Behaviour: Sendable {
            case succeed
            case fail(FinanceError)
            /// Échoue les `n` premières fois, puis réussit.
            case failThenSucceed(times: Int)
        }

        private var behaviour: Behaviour
        private(set) var createCalls = 0
        private(set) var confirmCalls = 0
        private(set) var readCalls = 0
        private var failuresSoFar = 0

        init(behaviour: Behaviour = .succeed) { self.behaviour = behaviour }

        private func envelope() -> PaymentEnvelope {
            PaymentEnvelope(
                id: "p-1", paymentType: .p2p, amount: 10, currency: "BIF",
                timestamp: Date(), status: .confirmed,
                senderId: "s-1", recipientId: "r-1", merchantId: nil,
                backendSignature: "sig",
                railProof: RailProof(
                    railProvider: "pgw", railTransactionId: "tx-1",
                    railSignature: "rs", railTimestamp: Date(),
                    railStatus: "OK", railMetadata: [:]
                ),
                evidenceRefs: [], version: "1",
                idempotencyKey: "k-1", correlationId: "c-1",
                description: nil, metadata: [:],
                feeAmount: nil, feeCurrency: nil, exchangeRate: nil,
                crossBorder: false
            )
        }

        private func resolveBehaviour() throws {
            switch behaviour {
            case .succeed:
                return
            case .fail(let error):
                throw error
            case .failThenSucceed(let times):
                if failuresSoFar < times {
                    failuresSoFar += 1
                    throw FinanceError.capabilityUnavailable
                }
            }
        }

        func capabilities() async throws -> FinanceCapabilities {
            readCalls += 1
            try resolveBehaviour()
            return FinanceCapabilities()
        }

        func financialObject(for reference: FinancialReference) async throws -> PaymentEnvelope {
            readCalls += 1
            try resolveBehaviour()
            return envelope()
        }

        func refresh(_ reference: FinancialReference) async throws -> PaymentEnvelope {
            readCalls += 1
            try resolveBehaviour()
            return envelope()
        }

        func createPaymentIntent(_ request: CreatePaymentIntentRequest,
                                 idempotency: IdempotencyContext) async throws -> PaymentEnvelope {
            createCalls += 1
            try resolveBehaviour()
            return envelope()
        }

        func confirmPaymentIntent(reference: FinancialReference,
                                  idempotency: IdempotencyContext,
                                  stepUp: StepUpAttestation?) async throws -> PaymentEnvelope {
            confirmCalls += 1
            try resolveBehaviour()
            return envelope()
        }
    }

    private func key() -> ProviderCircuitKey {
        ProviderCircuitKey(providerID: "pgw-1", operation: "payment")
    }

    private func request() -> CreatePaymentIntentRequest {
        CreatePaymentIntentRequest(type: .payment, amount: 10, currency: "BIF",
                                   recipientID: "r-1")
    }

    // MARK: - Les écritures ne se rejouent pas

    /// L'invariant du §15 sur le chemin réel : une création qui échoue **ne
    /// repart pas**. Relire coûte une requête ; réécrire coûte un second débit.
    @Test("Une création qui échoue n'est jamais rejouée")
    func createNeverRetries() async {
        let spy = SpyClient(behaviour: .fail(.capabilityUnavailable))
        let client = ResilientFinanceAPIClient(wrapping: spy, circuitKey: key())

        _ = try? await client.createPaymentIntent(
            request(), idempotency: IdempotencyContext.new(deviceID: "d")
        )
        #expect(await spy.createCalls == 1)
    }

    @Test("Une confirmation qui échoue n'est jamais rejouée")
    func confirmNeverRetries() async {
        let spy = SpyClient(behaviour: .fail(.timeoutUnknown))
        let client = ResilientFinanceAPIClient(wrapping: spy, circuitKey: key())
        let reference = FinancialReference(type: .payment, id: "p-1", version: 1,
                                           correlationID: CorrelationId())

        _ = try? await client.confirmPaymentIntent(
            reference: reference, idempotency: IdempotencyContext.new(deviceID: "d"), stepUp: nil
        )
        #expect(await spy.confirmCalls == 1)
    }

    // MARK: - Idempotence sur le chemin réel

    /// Deux appels, même clé, même contenu : **un seul appel réseau**.
    /// C'est la protection contre le double-clic et le retour arrière.
    @Test("Une clé rejouée n'atteint pas le backend deux fois")
    func replayedKeyHitsBackendOnce() async throws {
        let spy = SpyClient()
        let client = ResilientFinanceAPIClient(wrapping: spy, circuitKey: key())
        let context = IdempotencyContext.new(deviceID: "d")

        _ = try await client.createPaymentIntent(request(), idempotency: context)
        _ = try await client.createPaymentIntent(request(), idempotency: context)

        #expect(await spy.createCalls == 1)
    }

    /// Même clé, montant différent : refus. Rendre la réponse mémorisée
    /// débiterait un montant pour en afficher un autre.
    @Test("Une clé réutilisée pour un autre montant est refusée")
    func reusedKeyWithDifferentAmountIsRefused() async throws {
        let spy = SpyClient()
        let client = ResilientFinanceAPIClient(wrapping: spy, circuitKey: key())
        let context = IdempotencyContext.new(deviceID: "d")

        _ = try await client.createPaymentIntent(request(), idempotency: context)

        let different = CreatePaymentIntentRequest(type: .payment, amount: 999,
                                                   currency: "BIF", recipientID: "r-1")
        await #expect(throws: IdempotencyError.requestConflict) {
            _ = try await client.createPaymentIntent(different, idempotency: context)
        }
        // Le second n'a pas atteint le backend.
        #expect(await spy.createCalls == 1)
    }

    // MARK: - Les lectures réessaient

    /// Relire ne déplace rien : c'est le seul endroit où le réessai est sûr.
    @Test("Une lecture transitoirement en échec est réessayée")
    func readRetriesOnTransientFailure() async throws {
        let spy = SpyClient(behaviour: .failThenSucceed(times: 2))
        let client = ResilientFinanceAPIClient(
            wrapping: spy,
            readPolicy: RetryPolicy(maxAttempts: 4, baseDelay: 0.001, maxDelay: 0.002,
                                    jitterFactor: 0),
            circuitKey: key()
        )

        _ = try await client.capabilities()
        #expect(await spy.readCalls == 3)
    }

    @Test("Une lecture cesse de réessayer au plafond")
    func readStopsAtMaxAttempts() async {
        let spy = SpyClient(behaviour: .fail(.capabilityUnavailable))
        let client = ResilientFinanceAPIClient(
            wrapping: spy,
            readPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 0.001, maxDelay: 0.002,
                                    jitterFactor: 0),
            circuitKey: key()
        )

        _ = try? await client.capabilities()
        #expect(await spy.readCalls == 3)
    }

    // MARK: - Disjoncteur

    /// Le disjoncteur coupe les lectures après un seuil d'échecs : continuer à
    /// interroger un service tombé le maintient à terre.
    @Test("Le disjoncteur finit par couper les lectures")
    func breakerEventuallyBlocksReads() async {
        let spy = SpyClient(behaviour: .fail(.capabilityUnavailable))
        let breaker = ProviderCircuitBreaker(policy: ProviderCircuitPolicy(failureThreshold: 2))
        let client = ResilientFinanceAPIClient(
            wrapping: spy, breaker: breaker,
            readPolicy: RetryPolicy(maxAttempts: 1),
            circuitKey: key()
        )

        _ = try? await client.capabilities()
        _ = try? await client.capabilities()
        let callsBeforeTrip = await spy.readCalls

        _ = try? await client.capabilities()
        // Le troisième appel n'atteint plus le client enveloppé.
        #expect(await spy.readCalls == callsBeforeTrip)
    }

    /// **`refresh` passe malgré le disjoncteur.** C'est l'appel de la
    /// réconciliation : le bloquer ne réparerait un incident qu'une fois la
    /// panne finie, c'est-à-dire trop tard pour l'utilisateur qui attend.
    @Test("Le rafraîchissement passe même disjoncteur ouvert")
    func refreshBypassesOpenBreaker() async {
        let spy = SpyClient(behaviour: .fail(.capabilityUnavailable))
        let breaker = ProviderCircuitBreaker(policy: ProviderCircuitPolicy(failureThreshold: 1))
        let client = ResilientFinanceAPIClient(
            wrapping: spy, breaker: breaker,
            readPolicy: RetryPolicy(maxAttempts: 1), circuitKey: key()
        )
        let reference = FinancialReference(type: .payment, id: "p-1", version: 1,
                                           correlationID: CorrelationId())

        _ = try? await client.capabilities()   // ouvre le circuit
        let before = await spy.readCalls

        _ = try? await client.refresh(reference)
        #expect(await spy.readCalls == before + 1)
    }

    /// De même pour la confirmation : refuser localement de confirmer une
    /// intention déjà créée laisserait de l'argent dans un état que rien ne
    /// vient clarifier.
    @Test("La confirmation passe même disjoncteur ouvert")
    func confirmBypassesOpenBreaker() async {
        let spy = SpyClient(behaviour: .fail(.capabilityUnavailable))
        let breaker = ProviderCircuitBreaker(policy: ProviderCircuitPolicy(failureThreshold: 1))
        let client = ResilientFinanceAPIClient(
            wrapping: spy, breaker: breaker,
            readPolicy: RetryPolicy(maxAttempts: 1), circuitKey: key()
        )
        let reference = FinancialReference(type: .payment, id: "p-1", version: 1,
                                           correlationID: CorrelationId())

        _ = try? await client.capabilities()   // ouvre le circuit

        _ = try? await client.confirmPaymentIntent(
            reference: reference, idempotency: IdempotencyContext.new(deviceID: "d"), stepUp: nil
        )
        #expect(await spy.confirmCalls == 1)
    }

    /// Une réussite après des échecs referme le circuit : sinon une panne
    /// passagère condamnerait le service jusqu'au redémarrage.
    @Test("Une réussite referme le circuit")
    func successClosesBreaker() async throws {
        let spy = SpyClient(behaviour: .failThenSucceed(times: 1))
        let breaker = ProviderCircuitBreaker(policy: ProviderCircuitPolicy(failureThreshold: 5))
        let client = ResilientFinanceAPIClient(
            wrapping: spy, breaker: breaker,
            readPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.001, jitterFactor: 0),
            circuitKey: key()
        )

        _ = try await client.capabilities()
        #expect(await breaker.allowsAttempt(for: key()))
    }
}
