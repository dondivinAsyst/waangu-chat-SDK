//
//  FinancialCardPayloadTests.swift
//  FeatureChatTests
//
//  Un objet non vérifié ne s'affiche jamais comme abouti.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinancialCardPayloadTests: XCTestCase {

    private func payload(
        status: PaymentStatus = .confirmed,
        verification: FinancialCardVerification = .verified,
        version: Int = 1
    ) -> FinancialCardPayload {
        FinancialCardPayload(
            reference: FinanceFixtures.reference(version: version),
            status: status,
            amount: 1000,
            currency: "BIF",
            verification: verification
        )
    }

    /// Statut final **et** vérification réussie. L'un sans l'autre ne suffit pas.
    func test_settledRequiresBothStatusAndVerification() {
        XCTAssertTrue(payload(status: .confirmed, verification: .verified).canPresentAsSettled)
        XCTAssertFalse(payload(status: .confirmed, verification: .unverified).canPresentAsSettled)
        XCTAssertFalse(payload(status: .confirmed, verification: .rejected).canPresentAsSettled)
        XCTAssertFalse(payload(status: .processing, verification: .verified).canPresentAsSettled)
    }

    /// Un objet confirmé mais non vérifié doit repartir en réconciliation.
    func test_unverifiedObjectNeedsReconciliation() {
        XCTAssertTrue(payload(status: .confirmed, verification: .unverified).needsReconciliation)
        XCTAssertFalse(payload(status: .confirmed, verification: .verified).needsReconciliation)
    }

    func test_unknownStatusAlwaysNeedsReconciliation() {
        XCTAssertTrue(payload(status: .unknown, verification: .verified).needsReconciliation)
    }

    /// INTEGRATION_CHAT_FINANCE.md : on requête ce qui est parti après un
    /// execute (Phase 9, §3.3), pas ce qui attend une personne — une demande
    /// non réglée, un devis non confirmé. Ceux-là changent par `OBJECT_CHANGED`.
    func test_objectsWaitingForAPerson_areNotPolled() {
        for status in [PaymentStatus.pending, .compliancePending, .authorizationRequired,
                       .complianceHold, .amlReview, .refundRequested, .refundApproved] {
            XCTAssertFalse(payload(status: status, verification: .unverified).needsReconciliation, "\(status)")
        }
    }

    func test_objectsInFlightAfterExecute_arePolled() {
        for status in [PaymentStatus.queued, .processing, .authorized, .pendingProvider,
                       .pendingSettlement, .pendingReconciliation, .reconciling, .refundProcessing] {
            XCTAssertTrue(payload(status: status, verification: .unverified).needsReconciliation, "\(status)")
        }
    }

    func test_finalFailures_areNotPolled() {
        for status in [PaymentStatus.failed, .cancelled, .expired, .denied, .reversed, .refunded] {
            XCTAssertFalse(payload(status: status, verification: .unverified).needsReconciliation, "\(status)")
        }
    }

    /// Une relecture sans changement compte comme une lecture : sans cela, le
    /// délai de grâce ne s'écoulait jamais et l'objet était repris à chaque passe.
    func test_identicalRead_restartsTheGracePeriod() async {
        let store = FinancialObjectStore()
        let old = Date(timeIntervalSinceNow: -600)
        let object = FinancialCardPayload(reference: FinanceFixtures.reference(version: 3),
                                          status: .processing, amount: 1000, currency: "BIF",
                                          lastRefreshedAt: old)
        await store.apply(object)
        let scheduler = FinancialReconciliationScheduler(
            useCases: FinancialObjectUseCases(store: store, client: nil, guardian: nil,
                                              capabilities: MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities),
                                              logger: SilentLogger()),
            logger: SilentLogger())
        XCTAssertTrue(scheduler.isEligibleForSweep(object))

        await store.markChecked(object.reference)

        let checked = await store.current(for: object.reference)
        XCTAssertEqual(checked?.status, .processing)
        XCTAssertFalse(scheduler.isEligibleForSweep(checked!), "Relu à l'instant : pas avant deux minutes")
    }

    /// `merging` ne peut jamais effacer l'état courant, même appelé à tort.
    func test_mergingNeverLosesCurrentState() {
        let current = payload(version: 9)
        let stale = payload(status: .processing, version: 8)
        XCTAssertEqual(current.merging(stale).reference.version, 9)
        XCTAssertEqual(current.merging(stale).status, .confirmed)
    }

    func test_mergingAppliesNewerRevision() {
        let current = payload(status: .processing, version: 8)
        let newer = payload(status: .confirmed, version: 9)
        XCTAssertEqual(current.merging(newer).status, .confirmed)
    }

    /// Le total additionne ce que le backend a rendu — aucune règle de frais locale.
    func test_totalIncludesFeesWithoutRecomputing() {
        let withFee = FinancialCardPayload(
            reference: FinanceFixtures.reference(),
            status: .confirmed,
            amount: 1000,
            currency: "BIF",
            feeAmount: 25
        )
        XCTAssertEqual(withFee.totalAmount, 1025)
    }

    /// Un objet jamais synchronisé doit le dire, plutôt que de paraître à jour.
    func test_neverSyncedShowsExplicitLabel() {
        let stale = FinancialCardPayload(
            reference: FinanceFixtures.reference(),
            status: .unknown,
            amount: 10,
            currency: "BIF",
            lastRefreshedAt: .distantPast
        )
        XCTAssertEqual(stale.freshnessLabel, "Jamais synchronisé")
    }

    /// Un état lu à l'instant n'affiche pas d'horodatage : ce serait du bruit.
    func test_freshObjectShowsNoStamp() {
        XCTAssertNil(payload().freshnessLabel)
    }
}

// MARK: - Montants décimaux (tâche 4.3b)

final class FinancialAmountPrecisionTests: XCTestCase {

    /// Le cœur de 4.3b : un montant qu'un `Double` ne représente pas exactement
    /// doit survivre au passage en base.
    func test_exactDecimalSurvivesTheRoundTrip() throws {
        let exact = Decimal(string: "1234567.89")!

        let model = MessageContentModel(
            paymentAmount: NSDecimalNumber(decimal: exact).doubleValue,
            paymentCurrency: "BIF",
            paymentStatus: PaymentStatus.confirmed.rawValue,
            paymentRef: "obj-1",
            financialObjectType: FinancialObjectType.payment.rawValue,
            financialObjectVersion: 1,
            paymentAmountDecimal: NSDecimalNumber(decimal: exact).description
        )

        let payload = MessageModelMapper.buildFinancial(from: model)
        XCTAssertEqual(payload?.amount, exact)
    }

    /// Une ligne écrite avant 4.3b n'a pas de champ décimal : elle doit rester
    /// lisible, via le `Double`.
    func test_legacyRowWithoutDecimalStillDecodes() {
        let model = MessageContentModel(
            paymentAmount: 1500,
            paymentCurrency: "BIF",
            paymentStatus: PaymentStatus.confirmed.rawValue,
            paymentRef: "obj-legacy",
            financialObjectType: FinancialObjectType.payment.rawValue,
            financialObjectVersion: 1
        )

        let payload = MessageModelMapper.buildFinancial(from: model)
        XCTAssertEqual(payload?.amount, 1500)
    }

    /// En cas de divergence, le décimal l'emporte — c'est lui qui porte la valeur
    /// exacte, le `Double` n'est qu'une copie de compatibilité.
    func test_decimalWinsOverDouble() {
        let model = MessageContentModel(
            paymentAmount: 999,
            paymentCurrency: "BIF",
            paymentStatus: PaymentStatus.confirmed.rawValue,
            paymentRef: "obj-1",
            financialObjectType: FinancialObjectType.payment.rawValue,
            financialObjectVersion: 1,
            paymentAmountDecimal: "1000.05"
        )

        XCTAssertEqual(MessageModelMapper.buildFinancial(from: model)?.amount,
                       Decimal(string: "1000.05"))
    }

    /// Une ligne sans montant du tout ne produit pas de carte à zéro : elle ne
    /// produit pas de carte. Un montant inventé serait pire qu'une carte d'attente.
    func test_missingAmountYieldsNoCard() {
        let model = MessageContentModel(
            paymentCurrency: "BIF",
            paymentRef: "obj-1",
            financialObjectType: FinancialObjectType.payment.rawValue,
            financialObjectVersion: 1
        )
        XCTAssertNil(MessageModelMapper.buildFinancial(from: model))
    }
}
