import Testing
import Foundation
@testable import WaanguCoreKit

/// Idempotence, requête d'état et réessai — §15, §17, §18, §19.
///
/// Ces tests portent une seule idée : **le double débit naît d'une confusion
/// entre « incertain » et « échoué »**. Chaque cas ci-dessous ferme un chemin
/// par lequel cette confusion se réintroduirait.
@Suite("Bloc 6 — résilience financière")
struct Bloc6ResilienceTests {

    // MARK: - Registre d'idempotence (§17)

    @Test("Une clé jamais vue laisse passer l'opération")
    func unseenKeyPasses() async {
        let store = IdempotencyStore()
        #expect(await store.resolve(key: "k-1", requestHash: "h") == nil)
    }

    @Test("Une clé rejouée rend la réponse mémorisée")
    func replayedKeyReturnsStoredResponse() async {
        let store = IdempotencyStore()
        await store.store(key: "k-1", requestHash: "h", responseData: Data("ok".utf8), ttl: 60)

        guard case .success(let data)? = await store.resolve(key: "k-1", requestHash: "h") else {
            Issue.record("la réponse mémorisée n'a pas été rendue")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "ok")
    }

    /// **Le contrôle central.** Même clé, contenu différent : ce n'est pas un
    /// doublon, c'est une collision. Rendre la réponse mémorisée débiterait un
    /// montant pour en afficher un autre.
    @Test("Une clé réutilisée pour une autre requête est un conflit")
    func reusedKeyWithDifferentPayloadConflicts() async {
        let store = IdempotencyStore()
        await store.store(key: "k-1", requestHash: "h-1", responseData: Data(), ttl: 60)

        let verdict = await store.resolve(key: "k-1", requestHash: "h-2")
        #expect(verdict == .failure(.requestConflict))
    }

    @Test("Une entrée expirée est oubliée et laisse repasser")
    func expiredEntryIsForgotten() async {
        let now = Date()
        let store = IdempotencyStore()
        await store.store(key: "k-1", requestHash: "h", responseData: Data(), ttl: 10, now: now)

        #expect(await store.resolve(key: "k-1", requestHash: "h",
                                    now: now.addingTimeInterval(5)) != nil)
        #expect(await store.resolve(key: "k-1", requestHash: "h",
                                    now: now.addingTimeInterval(20)) == nil)
    }

    /// Un registre plein qui refuserait d'écrire perdrait la protection sur les
    /// opérations les plus récentes — celles qui sont en cours.
    @Test("Le registre borne sa taille en évinçant le plus ancien")
    func storeEvictsOldestWhenFull() async {
        let now = Date()
        let store = IdempotencyStore(capacity: 3)

        for index in 0..<3 {
            await store.store(key: "k-\(index)", requestHash: "h", responseData: Data(),
                              ttl: 600, now: now.addingTimeInterval(Double(index)))
        }
        await store.store(key: "k-3", requestHash: "h", responseData: Data(),
                          ttl: 600, now: now.addingTimeInterval(10))

        #expect(await store.count == 3)
        // La plus ancienne est partie, la plus récente est là.
        #expect(await store.resolve(key: "k-0", requestHash: "h",
                                    now: now.addingTimeInterval(10)) == nil)
        #expect(await store.resolve(key: "k-3", requestHash: "h",
                                    now: now.addingTimeInterval(10)) != nil)
    }

    @Test("Oublier une clé permet une nouvelle tentative légitime")
    func forgettingAllowsRetry() async {
        let store = IdempotencyStore()
        await store.store(key: "k-1", requestHash: "h", responseData: Data(), ttl: 600)
        await store.forget(key: "k-1")
        #expect(await store.resolve(key: "k-1", requestHash: "h") == nil)
    }

    // MARK: - Vérité financière (§19)

    /// Les quatre inégalités du §18.
    @Test("Incertain n'est jamais échoué")
    func uncertainIsNeverFailed() {
        for truth in [FinancialTruth.unknown, .pending, .processing] {
            #expect(truth.requiresRequery)
            #expect(!truth.permitsRetry)
            #expect(!truth.isSettled)
        }
        #expect(FinancialTruth.failed.permitsRetry)
        #expect(!FinancialTruth.failed.requiresRequery)
        #expect(FinancialTruth.confirmed.isSettled)
    }

    /// La projection est prudente **par construction** : se tromper vers
    /// `pending` fait attendre, se tromper vers `failed` fait payer deux fois.
    @Test("La projection des statuts ne fabrique jamais un échec")
    func projectionNeverInventsFailure() {
        let settled: [PaymentStatus] = [.confirmed, .completed]
        let genuineFailures: [PaymentStatus] = [.failed, .cancelled, .expired, .denied]

        for status in settled {
            #expect(FinancialTruth.from(status) == .confirmed)
        }
        for status in genuineFailures {
            #expect(FinancialTruth.from(status) == .failed)
        }

        // Tout le reste tombe dans une catégorie qui **n'autorise pas** le rejeu.
        for status in PaymentStatus.allCases
        where !settled.contains(status) && !genuineFailures.contains(status) {
            let truth = FinancialTruth.from(status)
            #expect(!truth.permitsRetry,
                    "\(status.rawValue) autorise un rejeu — risque de double débit")
        }
    }

    @Test("Un statut inconnu devient une issue inconnue, pas un échec")
    func unknownStatusBecomesUnknownTruth() {
        #expect(FinancialTruth.from(.unknown) == .unknown)
        #expect(FinancialTruth.from(.unknown) != .failed)
    }

    @Test("Une conformité en attente n'est pas un échec")
    func complianceHoldIsNotFailure() {
        #expect(FinancialTruth.from(.complianceHold) == .pending)
        #expect(FinancialTruth.from(.amlReview) == .pending)
        #expect(FinancialTruth.from(.authorizationRequired) == .pending)
    }

    /// `AUTHORIZED ≠ CAPTURED` : une autorisation est en cours, pas aboutie.
    @Test("Une autorisation n'est pas un aboutissement")
    func authorizedIsNotSettled() {
        #expect(FinancialTruth.from(.authorized) == .processing)
        #expect(!FinancialTruth.from(.authorized).isSettled)
    }

    // MARK: - Politique de réessai (§15)

    /// L'interdiction du §15, rendue structurelle : une écriture financière
    /// n'a qu'une tentative.
    @Test("Une écriture financière ne se rejoue pas")
    func financialWriteNeverRetries() {
        let policy = RetryPolicy.financialWrite
        #expect(policy.maxAttempts == 1)
        #expect(policy.nextDelay(afterAttempt: 1) == nil)
        #expect(!policy.permitsRetry(after: .failed, attempt: 1))
    }

    @Test("Le délai croît exponentiellement et se plafonne")
    func delayGrowsAndCaps() {
        let policy = RetryPolicy(maxAttempts: 8, baseDelay: 1, maxDelay: 8, jitterFactor: 0)

        #expect(policy.nextDelay(afterAttempt: 1, randomness: 0.5) == 1)
        #expect(policy.nextDelay(afterAttempt: 2, randomness: 0.5) == 2)
        #expect(policy.nextDelay(afterAttempt: 3, randomness: 0.5) == 4)
        #expect(policy.nextDelay(afterAttempt: 4, randomness: 0.5) == 8)
        // Plafonné : sans cela, la dixième tentative attendrait huit minutes.
        #expect(policy.nextDelay(afterAttempt: 7, randomness: 0.5) == 8)
    }

    /// Sans bruit, mille clients qui échouent ensemble réessaient ensemble, et
    /// la deuxième vague achève le service que la première a fait tomber.
    @Test("Le bruit écarte les délais sans jamais les rendre négatifs")
    func jitterSpreadsWithoutGoingNegative() {
        let policy = RetryPolicy(maxAttempts: 4, baseDelay: 1, maxDelay: 8, jitterFactor: 0.5)

        let low = policy.nextDelay(afterAttempt: 1, randomness: 0)
        let mid = policy.nextDelay(afterAttempt: 1, randomness: 0.5)
        let high = policy.nextDelay(afterAttempt: 1, randomness: 1)

        #expect(low == 0.5)
        #expect(mid == 1)
        #expect(high == 1.5)
        #expect(low! >= 0)

        // Même un bruit démesuré ne produit pas d'attente négative.
        let wild = RetryPolicy(maxAttempts: 2, baseDelay: 1, maxDelay: 8, jitterFactor: 5)
        #expect(wild.nextDelay(afterAttempt: 1, randomness: 0)! >= 0)
    }

    @Test("Aucun délai au-delà du nombre de tentatives")
    func noDelayBeyondMaxAttempts() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 1, jitterFactor: 0)
        #expect(policy.nextDelay(afterAttempt: 2, randomness: 0.5) != nil)
        #expect(policy.nextDelay(afterAttempt: 3, randomness: 0.5) == nil)
        #expect(policy.nextDelay(afterAttempt: 0, randomness: 0.5) == nil)
    }

    // MARK: - Décision d'exécution

    /// Le cœur de tout : un état incertain **interroge**, il ne rejoue pas.
    @Test("Une issue incertaine mène à une requête, jamais à un rejeu")
    func uncertainLeadsToRequery() {
        for truth in [FinancialTruth.unknown, .pending, .processing] {
            let decision = FinancialRetryDecision.decide(
                truth: truth, attempt: 1, policy: .read, randomness: 0.5
            )
            #expect(decision == .requery(after: 2), "\(truth) aurait dû mener à une requête")
        }
    }

    /// Requêter reste légitime même après avoir épuisé les réessais : ne plus
    /// pouvoir réessayer n'est pas une raison de renoncer à savoir.
    @Test("La requête survit à l'épuisement des tentatives")
    func requerySurvivesAttemptExhaustion() {
        let decision = FinancialRetryDecision.decide(
            truth: .unknown, attempt: 99, policy: .financialWrite, randomness: 0.5
        )
        #expect(decision == .requery(after: 2))
    }

    @Test("Une écriture financière incertaine ne rejoue jamais")
    func financialWriteNeverReplaysOnUncertainty() {
        for truth in [FinancialTruth.unknown, .pending, .processing] {
            let decision = FinancialRetryDecision.decide(
                truth: truth, attempt: 1, policy: .financialWrite, randomness: 0.5
            )
            if case .retry = decision {
                Issue.record("\(truth) a produit un rejeu sur une écriture financière")
            }
        }
    }

    @Test("Un échec avéré autorise un réessai borné")
    func genuineFailureRetriesWithinBounds() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 1, jitterFactor: 0)

        #expect(FinancialRetryDecision.decide(truth: .failed, attempt: 1,
                                              policy: policy, randomness: 0.5)
                == .retry(after: 1))
        #expect(FinancialRetryDecision.decide(truth: .failed, attempt: 3,
                                              policy: policy, randomness: 0.5)
                == .giveUp(reason: .attemptsExhausted))
    }

    @Test("Un aboutissement ne déclenche rien")
    func settledDoesNothing() {
        #expect(FinancialRetryDecision.decide(truth: .confirmed, attempt: 1,
                                              policy: .read, randomness: 0.5) == .settled)
    }

    /// Un mouvement inversé est terminé : réessayer relancerait un paiement que
    /// quelqu'un a délibérément annulé.
    @Test("Une opération inversée fait abandonner")
    func reversedGivesUp() {
        #expect(FinancialRetryDecision.decide(truth: .reversed, attempt: 1,
                                              policy: .read, randomness: 0.5)
                == .giveUp(reason: .reversed))
    }

    // MARK: - Intention marchande (§18)

    /// L'empreinte change avec le montant : c'est ce qui fait qu'une clé
    /// réutilisée pour un autre montant est détectée comme collision.
    @Test("L'empreinte de requête suit son contenu")
    func requestHashFollowsContent() {
        let identity = MerchantIdentitySnapshot(
            merchantID: "m-1", identityVersion: "id-1", policyVersion: "pol-1",
            verification: .verified, capturedAt: Date()
        )
        let bif = CurrencyCode(code: "BIF", exponent: 0)

        func request(amount: Int64, reference: String?) -> MerchantPaymentIntentRequest {
            MerchantPaymentIntentRequest(
                merchantID: "m-1", amount: Money(minorUnits: amount, currency: bif),
                reference: reference, identity: identity
            )
        }

        let base = request(amount: 1_000, reference: "r-1")
        #expect(base.requestHash == request(amount: 1_000, reference: "r-1").requestHash)
        #expect(base.requestHash != request(amount: 2_000, reference: "r-1").requestHash)
        #expect(base.requestHash != request(amount: 1_000, reference: "r-2").requestHash)
    }

    /// Une identité marchande différente change l'empreinte : payer le même
    /// montant à un marchand dont l'identité a bougé n'est pas la même requête.
    @Test("Une identité marchande modifiée change l'empreinte")
    func identityChangeAltersHash() {
        let bif = CurrencyCode(code: "BIF", exponent: 0)
        func request(identityVersion: String) -> MerchantPaymentIntentRequest {
            MerchantPaymentIntentRequest(
                merchantID: "m-1", amount: Money(minorUnits: 1_000, currency: bif),
                identity: MerchantIdentitySnapshot(
                    merchantID: "m-1", identityVersion: identityVersion,
                    policyVersion: "pol-1", verification: .verified, capturedAt: Date()
                )
            )
        }
        #expect(request(identityVersion: "id-1").requestHash
                != request(identityVersion: "id-2").requestHash)
    }

    @Test("Une intention expirée est détectée")
    func expiredIntentIsDetected() {
        let now = Date()
        let bif = CurrencyCode(code: "BIF", exponent: 0)
        func intent(expiresAt: Date?) -> MerchantPaymentIntent {
            MerchantPaymentIntent(
                id: "i-1",
                reference: FinancialReference(type: .payment, id: "p-1", version: 1,
                                              correlationID: CorrelationId()),
                amount: Money(minorUnits: 1_000, currency: bif), expiresAt: expiresAt
            )
        }
        #expect(intent(expiresAt: now.addingTimeInterval(-1)).hasExpired(at: now))
        #expect(!intent(expiresAt: now.addingTimeInterval(60)).hasExpired(at: now))
        #expect(!intent(expiresAt: nil).hasExpired(at: now))
    }
}
