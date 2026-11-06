//
//  FinanceErrorExplanationsTests.swift
//  FeatureChatTests
//
//  L'écran dit pourquoi ; la décision reste sur le code.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceErrorExplanationsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FinanceErrorExplanations.shared.clear()
    }

    override func tearDown() {
        FinanceErrorExplanations.shared.clear()
        super.tearDown()
    }

    // MARK: - Magasin

    func test_serverMessage_isReturnedForTheSameError_only() {
        let store = FinanceErrorExplanations()
        store.record(serverMessage: "Quote expired — request a new one", for: .expired)
        XCTAssertEqual(store.explanation(for: .expired), .server("Quote expired — request a new one"))
        XCTAssertNil(store.explanation(for: .duplicate))
    }

    func test_newerExplanation_replacesTheOlder() {
        let store = FinanceErrorExplanations()
        _ = store.refuse(.sessionLocked)
        store.record(serverMessage: "Service fermé dans ce pays", for: .capabilityUnavailable)
        XCTAssertEqual(store.explanation(for: .capabilityUnavailable), .server("Service fermé dans ce pays"))
    }

    func test_refusal_isRecorded_andReturnsTheGenericError() {
        let store = FinanceErrorExplanations()
        XCTAssertEqual(store.refuse(.confirmationDenied), .capabilityUnavailable,
                       "La logique voit toujours le même refus")
        XCTAssertEqual(store.explanation(for: .capabilityUnavailable), .refusal(.confirmationDenied))
    }

    /// Une explication répond à l'échec qui vient d'arriver, pas à un échec semblable plus tard.
    func test_explanationExpires() {
        let clock = TestClock()
        let store = FinanceErrorExplanations(now: { clock.now })
        store.record(serverMessage: "stale soon", for: .expired)
        clock.advance(by: FinanceErrorExplanations.lifetime + 1)
        XCTAssertNil(store.explanation(for: .expired))
    }

    /// Issue incertaine : jamais d'autre texte que le nôtre — un « échec »
    /// inviterait à payer deux fois.
    func test_inDoubt_neverTakesAnExplanation() {
        let store = FinanceErrorExplanations()
        store.record(serverMessage: "Payment failed", for: .timeoutUnknown)
        XCTAssertNil(store.explanation(for: .timeoutUnknown))
    }

    func test_sanitizing_dropsEmptyAndBareCodes_capsLength_collapsesSpaces() {
        XCTAssertNil(FinanceErrorExplanations.sanitized(nil))
        XCTAssertNil(FinanceErrorExplanations.sanitized("   \n "))
        XCTAssertNil(FinanceErrorExplanations.sanitized("CF_029"))
        XCTAssertEqual(FinanceErrorExplanations.sanitized("  Quote   expired\n now "), "Quote expired now")
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(FinanceErrorExplanations.sanitized(long)?.count, FinanceErrorExplanations.maxLength)
    }

    func test_clear_forgetsEverything() {
        let store = FinanceErrorExplanations()
        store.record(serverMessage: "x", for: .forbidden)
        _ = store.refuse(.safeMode)
        store.clear()
        XCTAssertNil(store.explanation(for: .forbidden))
        XCTAssertNil(store.explanation(for: .capabilityUnavailable))
    }

    // MARK: - Raisons de refus

    /// La raison n'existe **exactement** que lorsque l'écriture est refusée — sur
    /// toutes les combinaisons. Une raison sans refus, ou un refus sans raison,
    /// serait un écran qui ment.
    func test_refusalReasons_matchCanWriteAndCanConfirm_forEveryCombination() {
        for bits in 0..<(1 << 8) {
            func flag(_ i: Int) -> Bool { bits & (1 << i) != 0 }
            let status = FinanceSessionStatus(
                paymentsAllowed: flag(0), writeLocked: flag(1), safeModeActive: flag(2),
                serviceSuspended: flag(3), countryOpen: flag(4), currency: "BIF",
                financeReadAllowed: true, paymentPrepareAllowed: flag(5), paymentConfirmAllowed: flag(6))
            XCTAssertEqual(status.writeRefusal == nil, status.canWrite, "bits \(bits)")
            XCTAssertEqual(status.confirmRefusal == nil, status.canConfirm, "bits \(bits)")
        }
    }

    /// La raison sur laquelle l'utilisateur peut le moins agir passe en premier.
    func test_mostBlockingReason_comesFirst() {
        let status = FinanceSessionStatus(paymentsAllowed: false, writeLocked: true, safeModeActive: true,
                                          serviceSuspended: true, countryOpen: false, currency: "BIF")
        XCTAssertEqual(status.writeRefusal, .countryClosed)
    }

    // MARK: - Affichage

    func test_displayOrder_server_thenRefusal_thenOurs() {
        let ours = FinanceStrings.errorMessage(.capabilityUnavailable)

        _ = FinanceErrorExplanations.shared.refuse(.sessionLocked)
        XCTAssertEqual(FinanceStrings.errorMessage(.capabilityUnavailable),
                       FinanceStrings.refusalMessage(.sessionLocked))
        XCTAssertNotEqual(FinanceStrings.errorMessage(.capabilityUnavailable), ours)

        FinanceErrorExplanations.shared.record(serverMessage: "Le partenaire est en maintenance.",
                                               for: .capabilityUnavailable)
        XCTAssertEqual(FinanceStrings.errorMessage(.capabilityUnavailable), "Le partenaire est en maintenance.")

        FinanceErrorExplanations.shared.clear()
        XCTAssertEqual(FinanceStrings.errorMessage(.capabilityUnavailable), ours)
    }

    func test_everyRefusal_hasANonEmptyMessage() {
        let all: [FinanceWriteRefusal] = [.sessionUnavailable, .countryClosed, .serviceSuspended, .safeMode,
                                          .sessionLocked, .paymentsDisabled, .confirmationDenied,
                                          .highRiskUnavailable]
        for refusal in all {
            XCTAssertFalse(FinanceStrings.refusalMessage(refusal).isEmpty, "\(refusal)")
        }
    }

    // MARK: - De bout en bout, contre le JSON du contrat

    /// Un refus métier : le code décide (devis expiré), le texte serveur s'affiche.
    func test_businessRefusal_logicOnTheCode_displayOnTheText() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/send-money/prepare"] = #"""
        { "success": false, "message": null, "statusCode": 0, "data": null,
          "error": { "code": "CF_029", "message": "Le devis a expiré. Demandez-en un nouveau.", "details": null },
          "timestamp": "2026-09-17T12:00:01Z" }
        """#
        let (services, _) = FinanceSendMoneyTests.make(routes)

        let result = await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft())

        guard case .failure(let error) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(error, .expired, "La logique lit le code CF_029, pas le texte")
        XCTAssertEqual(FinanceStrings.errorMessage(error), "Le devis a expiré. Demandez-en un nouveau.")
    }

    /// Session verrouillée et reprise refusée : rien ne part, et l'écran dit
    /// « session à revalider » au lieu de « service indisponible ».
    func test_lockedSession_saysSessionLocked_andSendsNothing() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["GET /chat-core/financial/session/resume"] = FinanceCoreJSON.wrap(
            #"{ "userId": "usr_1", "locked": true, "expiresAt": "2099-09-09T12:15:00Z" }"#)
        routes["POST /chat-core/financial/session/resume"] = FinanceCoreJSON.error("CF_066")
        let (services, server) = FinanceSendMoneyTests.make(routes)

        let result = await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft())

        guard case .failure(let error) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(error, .capabilityUnavailable)
        XCTAssertEqual(FinanceStrings.errorMessage(error), FinanceStrings.refusalMessage(.sessionLocked))
        let prepares = await server.calls.filter { $0.route.hasSuffix("/prepare") }
        XCTAssertTrue(prepares.isEmpty)
    }

    func test_confirmWithoutPaymentConfirm_saysSo() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["GET /chat-core/security/capabilities"] = FinanceEligibilityTests.securityJSON(
            ["FINANCE_READ", "PAYMENT_PREPARE"])
        let (services, _) = FinanceSendMoneyTests.make(routes)
        let quote = try await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft()).get()

        do {
            _ = try await services.apiClient.confirmPaymentIntent(
                reference: quote.reference, idempotency: FinanceFixtures.idempotency(), stepUp: nil)
            XCTFail("Aucun execute sans PAYMENT_CONFIRM")
        } catch {
            let financeError = try XCTUnwrap(error as? FinanceError)
            XCTAssertEqual(FinanceStrings.errorMessage(financeError),
                           FinanceStrings.refusalMessage(.confirmationDenied))
        }
    }

    func test_cashOutWithoutRiskEngine_saysSecurityBlock() async {
        let (services, _) = FinanceQuotedOperationsTests.make()

        let result = await services.quotedOperations
            .prepare(.cashOut, body: [:], idempotency: FinanceFixtures.idempotency())

        guard case .failure(let error) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(FinanceStrings.errorMessage(error), FinanceStrings.refusalMessage(.highRiskUnavailable))
    }
}

private final class TestClock: @unchecked Sendable {
    private(set) var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
