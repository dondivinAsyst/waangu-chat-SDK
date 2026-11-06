//
//  Bloc4ContractsTests.swift
//  FeatureChatTests
//
//  GAP-02 à GAP-14 du Bloc 4.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

// MARK: - GAP-02 — Mandats

final class MandateTests: XCTestCase {

    private let bif = CurrencyCode(code: "BIF", exponent: 0)

    private func mandate(
        status: MandateStatus = .active,
        max: Money? = nil,
        start: Date = Date().addingTimeInterval(-3_600),
        expiry: Date? = nil
    ) -> Mandate {
        Mandate(
            id: "m-1", creditorID: "regideso", creditorDisplayName: "REGIDESO",
            maxAmount: max, frequency: .monthly, startDate: start, expiryDate: expiry,
            consentVersion: "v3", consentEvidenceID: "ev-1", status: status
        )
    }

    /// **Un consentement présumé n'en est pas un.** Un mandat autorise des
    /// débits futurs sans geste de l'utilisateur.
    func test_draftIsNotSubmittableWithoutConsent() {
        let draft = MandateDraft(
            creditorID: "c", maxAmount: nil, frequency: .monthly,
            startDate: Date(), expiryDate: nil,
            consentVersion: "v3", hasConsented: false
        )
        XCTAssertFalse(draft.isSubmittable)
    }

    /// Sans version de texte, on sait que l'utilisateur a consenti mais pas
    /// **à quoi** — la preuve serait inexploitable en contestation.
    func test_draftRequiresAConsentVersion() {
        let draft = MandateDraft(
            creditorID: "c", maxAmount: nil, frequency: .monthly,
            startDate: Date(), expiryDate: nil,
            consentVersion: "", hasConsented: true
        )
        XCTAssertFalse(draft.isSubmittable)
    }

    func test_onlyActiveMandatesDebit() {
        XCTAssertTrue(mandate(status: .active).allowsDebit())
        for blocked in [MandateStatus.pendingConsent, .pendingApproval, .suspended, .expired, .revoked, .failed] {
            XCTAssertFalse(mandate(status: blocked).allowsDebit(), "\(blocked)")
        }
    }

    /// Un mandat actif mais non commencé ne prélève pas.
    func test_futureStartDateBlocksDebit() {
        XCTAssertFalse(mandate(start: Date().addingTimeInterval(86_400)).allowsDebit())
    }

    func test_expiredMandateDoesNotDebit() {
        XCTAssertFalse(mandate(expiry: Date().addingTimeInterval(-1)).allowsDebit())
    }

    /// Un plafond absent ne vaut pas plafond infini côté client : la borne est
    /// ailleurs, et le client ne la valide pas.
    func test_missingCeilingDoesNotMeanUnlimitedLocally() {
        XCTAssertTrue(mandate(max: nil).permits(amount: Money(minorUnits: 999_999, currency: bif)))
    }

    func test_ceilingIsEnforcedWithinACurrency() {
        let m = mandate(max: Money(minorUnits: 50_000, currency: bif))
        XCTAssertTrue(m.permits(amount: Money(minorUnits: 50_000, currency: bif)))
        XCTAssertFalse(m.permits(amount: Money(minorUnits: 50_001, currency: bif)))
    }

    /// Un plafond dans une autre devise ne s'applique pas — et ne se convertit
    /// surtout pas côté client.
    func test_ceilingInAnotherCurrencyRefuses() {
        let m = mandate(max: Money(minorUnits: 50_000, currency: bif))
        let cad = CurrencyCode(code: "CAD", exponent: 2)
        XCTAssertFalse(m.permits(amount: Money(minorUnits: 100, currency: cad)))
    }

    /// Révoqué et expiré ne revivent jamais.
    func test_terminalStatesNeverReopen() {
        for terminal in [MandateStatus.revoked, .expired] {
            for target in MandateStatus.allCases where target != terminal {
                XCTAssertFalse(
                    MandateStateMachine.isAllowed(from: terminal, to: target),
                    "\(terminal) -> \(target)"
                )
            }
        }
    }

    func test_suspendedCanResume() {
        XCTAssertTrue(MandateStateMachine.isAllowed(from: .suspended, to: .active))
    }

    /// Un état inconnu devient `suspended` : ni actif — ce qui autoriserait des
    /// débits sur un état incompris — ni révoqué, ce qui détruirait un mandat
    /// peut-être valide.
    func test_unknownStatusFallsBackToSuspended() throws {
        let decoded = try JSONDecoder().decode(
            MandateStatus.self, from: Data("\"SOMETHING_NEW\"".utf8)
        )
        XCTAssertEqual(decoded, .suspended)
        XCTAssertFalse(decoded.allowsExecution)
    }

    /// Une fréquence inconnue est refusée : traiter un trimestriel comme un
    /// mensuel triplerait le nombre de débits.
    func test_unknownFrequencyIsRefused() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(MandateFrequency.self, from: Data("\"HOURLY\"".utf8))
        )
    }

    /// La révocation échoue bruyamment sans backend.
    func test_closedRevokeFailsLoudly() async {
        let result = await ClosedMandateManaging().revoke("m-1", idempotency: FinanceFixtures.idempotency())
        guard case .failure = result else { return XCTFail("doit échouer visiblement") }
    }
}

// MARK: - GAP-03 — Porteurs de valeur

final class DeliveredSecretTests: XCTestCase {

    private func secret(_ value: String = "12345678901234567890") -> DeliveredSecret {
        DeliveredSecret(
            deliveryID: "d-1", reference: FinanceFixtures.reference(),
            kind: .electricityToken, value: value,
            subjectLabel: "Compteur 4821", issuedAt: Date()
        )
    }

    /// **Le type refuse de se décrire en entier.** Une interpolation dans un log
    /// est la manière la plus banale de faire fuir un porteur de valeur.
    func test_descriptionNeverLeaksTheValue() {
        let s = secret()
        XCTAssertFalse(s.description.contains("12345678901234567890"))
        XCTAssertTrue(s.description.contains("redacted"))
    }

    func test_maskedValueRevealsOnlyLastFour() {
        XCTAssertTrue(secret().maskedValue.hasSuffix("7890"))
        XCTAssertFalse(secret().maskedValue.contains("1234567890123456"))
    }

    /// Un jeton de 20 chiffres se saisit sur un compteur : par groupes de
    /// quatre, il se relit sans se perdre.
    func test_groupedValueIsReadable() {
        XCTAssertEqual(secret().groupedValue, "1234 5678 9012 3456 7890")
    }

    /// Lu d'un bloc, un jeton devient un nombre astronomique.
    func test_spelledValueIsDigitByDigit() {
        XCTAssertEqual(secret("1234").spelledValue, "1 2 3 4")
    }

    /// Le repli est la politique la plus stricte : un secret qu'on n'a pas su
    /// classer est traité comme le plus sensible.
    func test_strictPolicyForbidsEverything() {
        XCTAssertTrue(SecretRevealPolicy.strict.requireBiometric)
        XCTAssertFalse(SecretRevealPolicy.strict.allowCopy)
        XCTAssertFalse(SecretRevealPolicy.strict.allowShare)
        XCTAssertEqual(SecretRevealPolicy.strict.autoHideAfter, 30)
    }
}

// MARK: - GAP-04 — Idempotence et payload

final class IdempotencyPayloadGuardTests: XCTestCase {

    private let payload = ["amount": "5000", "recipient": "rcpt-1"]

    func test_firstUseIsAccepted() {
        XCTAssertEqual(
            IdempotencyPayloadGuard.verdict(storedHash: nil, incoming: payload),
            .firstUse
        )
    }

    /// Un retry légitime réutilise la clé **et** le contenu.
    func test_sameContentIsARetry() {
        let hash = IdempotencyPayloadGuard.hash(payload)
        XCTAssertEqual(
            IdempotencyPayloadGuard.verdict(storedHash: hash, incoming: payload),
            .sameIntent
        )
    }

    /// **Le défaut que la clé seule ne détectait pas.** Même clé, montant
    /// différent : le backend aurait rendu la réponse de la première opération
    /// pour une intention qui n'est plus la même.
    func test_sameKeyDifferentAmountIsAConflict() {
        let hash = IdempotencyPayloadGuard.hash(payload)
        let tampered = ["amount": "500000", "recipient": "rcpt-1"]
        guard case .conflict = IdempotencyPayloadGuard.verdict(storedHash: hash, incoming: tampered)
        else { return XCTFail("un montant différent sous la même clé est un conflit") }
    }

    func test_sameKeyDifferentRecipientIsAConflict() {
        let hash = IdempotencyPayloadGuard.hash(payload)
        let tampered = ["amount": "5000", "recipient": "rcpt-2"]
        guard case .conflict = IdempotencyPayloadGuard.verdict(storedHash: hash, incoming: tampered)
        else { return XCTFail("un bénéficiaire différent est un conflit") }
    }

    /// L'ordre de sérialisation JSON n'est pas garanti : deux encodages du même
    /// contenu doivent donner la même empreinte.
    func test_hashIsIndependentOfKeyOrder() {
        XCTAssertEqual(
            IdempotencyPayloadGuard.hash(["b": "2", "a": "1"]),
            IdempotencyPayloadGuard.hash(["a": "1", "b": "2"])
        )
    }
}

// MARK: - GAP-05 — Configuration périmée

final class ConfigurationVersionTests: XCTestCase {

    func test_headersCarryEveryVersion() {
        let v = ConfigurationVersions(
            catalogVersion: "c-12", workflowVersion: "w-3", schemaVersion: "s-1"
        )
        XCTAssertEqual(v.httpHeaders["X-Catalog-Version"], "c-12")
        XCTAssertEqual(v.httpHeaders["X-Workflow-Version"], "w-3")
        XCTAssertEqual(v.httpHeaders["X-Schema-Version"], "s-1")
    }

    func test_absentWorkflowIsOmittedNotEmpty() {
        let v = ConfigurationVersions(catalogVersion: "c-12", schemaVersion: "s-1")
        XCTAssertNil(v.httpHeaders["X-Workflow-Version"])
        XCTAssertEqual(v.httpHeaders.count, 2)
    }

    /// **Sans version exigée, il n'y a rien à rafraîchir.** Le composant a été
    /// retiré ; proposer « réessayer » enverrait l'utilisateur en boucle.
    func test_withdrawnComponentIsNotRecoverableByRefresh() {
        let withdrawn = StaleConfigurationRejection(staleComponent: .catalog, requiredVersion: nil)
        XCTAssertFalse(withdrawn.isRecoverableByRefresh)

        let outdated = StaleConfigurationRejection(staleComponent: .catalog, requiredVersion: "c-13")
        XCTAssertTrue(outdated.isRecoverableByRefresh)
    }
}

// MARK: - GAP-07 / GAP-14 — Inbox et détection de trou

final class EventInboxTests: XCTestCase {

    private let policy = EventInboxPolicy()

    private func event(_ version: Int, id: String = UUID().uuidString,
                       schema: SchemaVersion = SchemaVersion(major: 1, minor: 0)) -> EventEnvelope {
        EventEnvelope(
            eventID: id, eventType: "financial_object.updated", schemaVersion: schema,
            aggregateID: "obj-1", aggregateVersion: version, occurredAt: Date(),
            producer: "biller", correlationID: CorrelationId(value: "c-1")
        )
    }

    func test_firstEventIsAcceptedWithoutGap() {
        XCTAssertEqual(
            policy.verdict(for: event(7), lastAppliedVersion: nil, seenEventIDs: []),
            .accept
        )
    }

    func test_nextInSequenceIsAccepted() {
        XCTAssertEqual(
            policy.verdict(for: event(8), lastAppliedVersion: 7, seenEventIDs: []),
            .accept
        )
    }

    /// **Un rejeu est un fait normal d'un transport au-moins-une-fois**, pas un
    /// incident — et surtout pas un trou.
    func test_duplicateIsIgnoredNotTreatedAsGap() {
        let e = event(8, id: "evt-8")
        XCTAssertEqual(
            policy.verdict(for: e, lastAppliedVersion: 7, seenEventIDs: ["evt-8"]),
            .duplicate
        )
    }

    /// La déduplication passe **avant** tout le reste.
    func test_duplicateWinsOverStaleness() {
        let e = event(3, id: "evt-3")
        XCTAssertEqual(
            policy.verdict(for: e, lastAppliedVersion: 9, seenEventIDs: ["evt-3"]),
            .duplicate
        )
    }

    func test_olderVersionIsStale() {
        XCTAssertEqual(
            policy.verdict(for: event(5), lastAppliedVersion: 9, seenEventIDs: []),
            .stale(current: 9)
        )
    }

    /// **GAP-14.** v10 puis v12 : v11 manque, et on ignore ce qu'elle disait.
    /// L'événement n'est pas appliqué à l'aveugle.
    func test_gapIsDetectedWithItsBounds() {
        XCTAssertEqual(
            policy.verdict(for: event(12), lastAppliedVersion: 9, seenEventIDs: []),
            .gap(missingFrom: 10, missingTo: 11)
        )
    }

    /// Un `major` supérieur n'est pas lisible : le client ne sait pas ce qu'il
    /// lirait. Un `minor` supérieur l'est, en ignorant l'inconnu.
    func test_majorSchemaBumpIsUnsupportedMinorIsFine() {
        let futureMajor = event(8, schema: SchemaVersion(major: 2, minor: 0))
        XCTAssertEqual(
            policy.verdict(for: futureMajor, lastAppliedVersion: 7, seenEventIDs: []),
            .unsupportedSchema
        )
        let futureMinor = event(8, schema: SchemaVersion(major: 1, minor: 9))
        XCTAssertEqual(
            policy.verdict(for: futureMinor, lastAppliedVersion: 7, seenEventIDs: []),
            .accept
        )
    }
}

// MARK: - GAP-13 — Kill switch

final class KillSwitchTests: XCTestCase {

    func test_nothingSuspendedAllowsEverything() {
        XCTAssertTrue(KillSwitchState.none.allows(providerID: "regideso", country: "BI"))
        XCTAssertFalse(KillSwitchState.none.isAnythingSuspended)
    }

    /// **Une seule dimension suffit à fermer.** Une opération autorisée par
    /// quatre dimensions et suspendue par la cinquième reste suspendue.
    func test_anySingleDimensionCloses() {
        let byProvider = KillSwitchState(suspendedProviders: ["regideso"])
        XCTAssertFalse(byProvider.allows(providerID: "regideso"))
        XCTAssertTrue(byProvider.allows(providerID: "autre"))

        let byCountry = KillSwitchState(suspendedCountries: ["BI"])
        XCTAssertFalse(byCountry.allows(providerID: "autre", country: "BI"))
    }

    func test_fullSuspensionOverridesEverything() {
        let all = KillSwitchState.everything
        XCTAssertFalse(all.allows(providerID: "n'importe lequel"))
        XCTAssertTrue(all.entireFinancialLayerSuspended)
    }

    /// Le repli en cas d'échec de lecture suspend tout — c'est écrit dans le
    /// protocole, et `everything` porte son motif.
    func test_readFailureFallbackCarriesAReason() {
        XCTAssertNotNil(KillSwitchState.everything.reasonKey)
    }
}

// MARK: - GAP-08 — Audit métier

final class FinancialAuditEventTests: XCTestCase {

    /// **Le filtre est dans le constructeur**, pas au site d'appel : un journal
    /// d'audit est consulté après incident, quand personne ne relit les appelants.
    func test_forbiddenKeysNeverEnterTheJournal() {
        let event = FinancialAuditEvent(
            action: .secretRevealed, category: .delivery,
            actorID: "u-1", actorType: "user",
            resourceIDHash: "abc", correlationID: CorrelationId(value: "c"),
            metadata: [
                "token": "12345678901234567890",
                "pin": "1234",
                "provider": "regideso"
            ]
        )
        XCTAssertNil(event.metadata["token"])
        XCTAssertNil(event.metadata["pin"])
        XCTAssertEqual(event.metadata["provider"], "regideso")
    }

    func test_everyDomainHasAnAuditCategory() {
        XCTAssertEqual(FinancialAuditCategory.allCases.count, 7)
    }
}

// MARK: - GAP-09 — Les trois états facturiers

final class BillerPaymentStatesTests: XCTestCase {

    private let added: [PaymentStatus] = [
        .compliancePending, .authorizationRequired, .pendingReconciliation
    ]

    func test_addedStatesAreInFlightNotTerminal() {
        for status in added {
            XCTAssertTrue(status.isInFlight, "\(status)")
            XCTAssertFalse(status.isTerminal, "\(status)")
        }
    }

    /// **La règle du Bloc 2, tenue une fois de plus.** Aucun état ajouté ne peut
    /// annoncer un succès — `pendingReconciliation` en particulier : l'utilisateur
    /// est débité, le fournisseur n'a pas confirmé.
    func test_noAddedStateCanAnnounceSuccess() {
        for status in added {
            for verification in [FinancialCardVerification.verified, .unverified, .rejected] {
                let payload = FinancialCardPayloadFixture.make(status: status, verification: verification)
                XCTAssertFalse(payload.presentation.announcesSuccess, "\(status) / \(verification)")
            }
        }
    }

    func test_pendingReconciliationShowsAsReconciling() {
        let p = FinancialCardPayloadFixture.make(status: .pendingReconciliation, verification: .verified)
        XCTAssertEqual(p.presentation, .reconciling)
    }

    func test_addedStatesDecodeExactly() throws {
        let pairs: [(String, PaymentStatus)] = [
            ("COMPLIANCE_PENDING", .compliancePending),
            ("AUTHORIZATION_REQUIRED", .authorizationRequired),
            ("PENDING_RECONCILIATION", .pendingReconciliation)
        ]
        for (raw, expected) in pairs {
            XCTAssertEqual(
                try JSONDecoder().decode(PaymentStatus.self, from: Data("\"\(raw)\"".utf8)),
                expected
            )
        }
    }
}

// MARK: - GAP-10 — Le plancher de step-up vient du backend

final class StepUpFloorTests: XCTestCase {

    private func envelope(requiredLevel: StepUpLevel?) -> PaymentEnvelope {
        var metadata: [String: String] = [:]
        if let requiredLevel { metadata["required_step_up"] = "\(requiredLevel.rawValue)" }
        return PaymentEnvelope(
            id: "obj-1", paymentType: .p2p, amount: 1_000, currency: "BIF",
            timestamp: Date(), status: .pending,
            senderId: "s", recipientId: "r", merchantId: nil,
            backendSignature: "sig", railProof: RailProof(
                railProvider: "", railTransactionId: "", railSignature: "",
                railTimestamp: Date(), railStatus: "", railMetadata: [:]
            ),
            evidenceRefs: [], version: "1", idempotencyKey: "k",
            correlationId: "c", description: nil, metadata: metadata,
            feeAmount: nil, feeCurrency: nil, exchangeRate: nil, crossBorder: false
        )
    }

    /// Le niveau exigé est lu depuis l'enveloppe backend.
    func test_requiredLevelComesFromTheEnvelope() {
        XCTAssertEqual(envelope(requiredLevel: .fullReauth).requiredStepUpLevel, .fullReauth)
        XCTAssertEqual(envelope(requiredLevel: .pin).requiredStepUpLevel, .pin)
    }

    /// **Sans instruction backend, la valeur sûre est la plus exigeante
    /// atteignable localement.** Un plancher trop bas laisse passer ; un
    /// plancher trop haut ne coûte qu'un geste.
    func test_absentLevelMeansTheClientMustNotGuessLow() {
        XCTAssertNil(envelope(requiredLevel: nil).requiredStepUpLevel)

        // C'est le site d'appel qui applique le repli — vérifié ici pour que la
        // règle soit épinglée quelque part.
        let fallback = envelope(requiredLevel: nil).requiredStepUpLevel ?? .biometric
        XCTAssertEqual(fallback, .biometric)
        XCTAssertGreaterThan(fallback, StepUpLevel.pin)
    }

    /// Une valeur illisible ne devient pas `.none` : elle devient « absente »,
    /// donc soumise au repli exigeant.
    func test_unparseableLevelIsTreatedAsAbsent() {
        var metadata = ["required_step_up": "pas-un-entier"]
        let e = PaymentEnvelope(
            id: "o", paymentType: .p2p, amount: 1, currency: "BIF", timestamp: Date(),
            status: .pending, senderId: "s", recipientId: "r", merchantId: nil,
            backendSignature: "", railProof: RailProof(
                railProvider: "", railTransactionId: "", railSignature: "",
                railTimestamp: Date(), railStatus: "", railMetadata: [:]
            ),
            evidenceRefs: [], version: "1", idempotencyKey: "k", correlationId: "c",
            description: nil, metadata: metadata, feeAmount: nil, feeCurrency: nil,
            exchangeRate: nil, crossBorder: false
        )
        metadata.removeAll()
        XCTAssertNil(e.requiredStepUpLevel)
    }
}

// MARK: - GAP-11 — Coupe-circuit par fournisseur

final class ProviderCircuitBreakerTests: XCTestCase {

    private let regideso = ProviderCircuitKey(providerID: "regideso", operation: "pay")
    private let mtn = ProviderCircuitKey(providerID: "mtn", operation: "pay")

    func test_startsClosed() async {
        let breaker = ProviderCircuitBreaker()
        let allows = await breaker.allowsAttempt(for: regideso)
        XCTAssertTrue(allows)
    }

    func test_opensAfterThreshold() async {
        let breaker = ProviderCircuitBreaker(policy: ProviderCircuitPolicy(failureThreshold: 3))
        for _ in 0..<3 { await breaker.recordFailure(for: regideso) }
        let allows = await breaker.allowsAttempt(for: regideso)
        XCTAssertFalse(allows)
    }

    /// **Le point de GAP-11.** Un fournisseur en panne ne doit pas couper les
    /// autres : c'est la différence entre « REGIDESO ne répond plus » et
    /// « le réseau est coupé ».
    func test_oneProviderFailingDoesNotCloseAnother() async {
        let breaker = ProviderCircuitBreaker(policy: ProviderCircuitPolicy(failureThreshold: 2))
        for _ in 0..<3 { await breaker.recordFailure(for: regideso) }

        let regidesoAllows = await breaker.allowsAttempt(for: regideso)
        let mtnAllows = await breaker.allowsAttempt(for: mtn)
        XCTAssertFalse(regidesoAllows)
        XCTAssertTrue(mtnAllows, "MTN n'a rien fait de mal")
    }

    /// Chez un même fournisseur, la consultation peut répondre alors que
    /// l'exécution est tombée. Fermer les deux priverait l'utilisateur d'une
    /// information qui, elle, fonctionne.
    func test_operationsAreSegmentedWithinAProvider() async {
        let breaker = ProviderCircuitBreaker(policy: ProviderCircuitPolicy(failureThreshold: 2))
        let inquiry = ProviderCircuitKey(providerID: "regideso", operation: "inquiry")
        for _ in 0..<2 { await breaker.recordFailure(for: regideso) }

        let payAllows = await breaker.allowsAttempt(for: regideso)
        let inquiryAllows = await breaker.allowsAttempt(for: inquiry)
        XCTAssertFalse(payAllows)
        XCTAssertTrue(inquiryAllows)
    }

    /// Le passage `open → halfOpen` est fonction du temps : sans lui, un
    /// circuit ouvert le resterait jusqu'à ce que quelqu'un tente un appel —
    /// c'est-à-dire jamais, puisqu'il est ouvert.
    func test_reopensForProbingAfterTheDelay() async {
        let breaker = ProviderCircuitBreaker(
            policy: ProviderCircuitPolicy(failureThreshold: 1, openDuration: 30)
        )
        let now = Date()
        await breaker.recordFailure(for: regideso, now: now)

        let immediately = await breaker.state(for: regideso, now: now)
        XCTAssertEqual(immediately, .open)

        let later = await breaker.state(for: regideso, now: now.addingTimeInterval(31))
        XCTAssertEqual(later, .halfOpen)
        XCTAssertTrue(later.allowsAttempt)
    }

    /// Un échec en sondage rouvre immédiatement : le fournisseur n'est pas
    /// rétabli, et insister allongerait l'incident.
    func test_failureWhileProbingReopensAtOnce() async {
        let breaker = ProviderCircuitBreaker(
            policy: ProviderCircuitPolicy(failureThreshold: 1, openDuration: 10)
        )
        let now = Date()
        await breaker.recordFailure(for: regideso, now: now)
        let probing = now.addingTimeInterval(11)
        await breaker.recordFailure(for: regideso, now: probing)

        let state = await breaker.state(for: regideso, now: probing)
        XCTAssertEqual(state, .open)
    }

    func test_enoughSuccessesCloseTheCircuit() async {
        let breaker = ProviderCircuitBreaker(
            policy: ProviderCircuitPolicy(failureThreshold: 1, openDuration: 10, successesToClose: 2)
        )
        let now = Date()
        await breaker.recordFailure(for: regideso, now: now)
        let probing = now.addingTimeInterval(11)
        await breaker.recordSuccess(for: regideso, now: probing)
        await breaker.recordSuccess(for: regideso, now: probing)

        let state = await breaker.state(for: regideso, now: probing)
        XCTAssertEqual(state, .closed)
    }

    func test_openCircuitsAreObservable() async {
        let breaker = ProviderCircuitBreaker(policy: ProviderCircuitPolicy(failureThreshold: 1))
        await breaker.recordFailure(for: regideso)
        let open = await breaker.openCircuits()
        XCTAssertEqual(open, [regideso])
    }
}

// MARK: - GAP-12 — Paquet de support

final class SupportContextPackageTests: XCTestCase {

    func test_referenceAndCorrelationAreCarried() {
        let ref = FinanceFixtures.reference(version: 4)
        let pkg = SupportContextPackage.from(reference: ref, observedStatus: .unknown)

        XCTAssertEqual(pkg.paymentIntentID, ref.id)
        XCTAssertEqual(pkg.correlationID, ref.correlationID)
        XCTAssertTrue(pkg.isActionable)
    }

    /// Le support n'a pas besoin du numéro de compteur entier pour identifier
    /// un dossier.
    func test_customerReferenceIsMasked() {
        let pkg = SupportContextPackage(
            customerReference: "0123456789",
            observedStatus: .failed,
            correlationID: CorrelationId(value: "c-1")
        )
        XCTAssertEqual(pkg.maskedCustomerReference, "••••••6789")
        XCTAssertFalse(pkg.maskedCustomerReference?.contains("012345") ?? false)
    }

    func test_shortReferenceIsFullyMasked() {
        let pkg = SupportContextPackage(
            customerReference: "123",
            observedStatus: .failed,
            correlationID: CorrelationId(value: "c")
        )
        XCTAssertEqual(pkg.maskedCustomerReference, "•••")
    }

    /// Sans corrélation ni référence, le support reçoit une plainte qu'il ne
    /// peut rattacher à rien.
    func test_packageWithoutReferenceIsNotActionable() {
        let pkg = SupportContextPackage(
            observedStatus: .failed,
            correlationID: CorrelationId(value: "c-1")
        )
        XCTAssertFalse(pkg.isActionable)
    }

    /// Seules les **références** de preuve circulent, jamais leur contenu.
    func test_onlyEvidenceReferencesTravel() {
        let pkg = SupportContextPackage(
            paymentIntentID: "p-1",
            observedStatus: .failed,
            correlationID: CorrelationId(value: "c"),
            evidenceReferences: ["doc-1", "doc-2"]
        )
        XCTAssertEqual(pkg.evidenceReferences, ["doc-1", "doc-2"])
    }
}

// MARK: - GAP-15 — Persistance

final class FinancialPersistenceTests: XCTestCase {

    private func stored(_ status: PaymentStatus) -> PersistedFinancialObject {
        PersistedFinancialObject(
            type: "PAYMENT", id: "obj-1", version: 3,
            status: status.rawValue, lastKnownAt: Date()
        )
    }

    /// **Le défaut que GAP-15 ferme.** Un paiement laissé en `unknown` par un
    /// kill d'application doit être repris au lancement suivant.
    func test_nonTerminalObjectsAreReconciledOnLaunch() {
        for status in [PaymentStatus.unknown, .processing, .pendingProvider, .reconciling] {
            XCTAssertTrue(stored(status).needsReconciliationOnLaunch, "\(status)")
        }
    }

    /// Les états finaux ne changeront plus : les requêter à chaque lancement
    /// produirait une salve d'appels inutiles.
    func test_terminalObjectsAreNotReconciled() {
        for status in [PaymentStatus.completed, .failed, .cancelled, .refunded] {
            XCTAssertFalse(stored(status).needsReconciliationOnLaunch, "\(status)")
        }
    }

    /// Un statut que cette version ne connaît pas est repris : c'est le cas
    /// d'un client mis à jour après un changement backend, et l'ignorer
    /// laisserait un objet dans un état illisible.
    func test_unknownStoredStatusIsReconciled() {
        let future = PersistedFinancialObject(
            type: "PAYMENT", id: "o", version: 1,
            status: "SOMETHING_FROM_NEXT_YEAR", lastKnownAt: Date()
        )
        XCTAssertTrue(future.needsReconciliationOnLaunch)
    }

    func test_identityKeyMatchesTheReferenceFormat() {
        XCTAssertEqual(stored(.pending).identityKey, "PAYMENT:obj-1")
    }
}
