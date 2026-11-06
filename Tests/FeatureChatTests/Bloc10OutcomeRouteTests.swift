//
//  Bloc10OutcomeRouteTests.swift
//  FeatureChatTests
//
//  Chapitres 78 et 80 — une issue inconnue n'est jamais un échec.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinancialOutcomeRouteTests: XCTestCase {

    private let reference = FinancialReference(
        type: .payment, id: "tx-42", version: 1, correlationID: CorrelationId(value: "c-42")
    )

    // MARK: - §80 — « Ne jamais transformer Timeout en Transaction failed »

    func test_timeoutAfterSubmission_routesToVerifying_neverFailed() {
        let route = FinancialOutcomeRoute.route(.failed(.timeoutUnknown),
                                                submittedReference: reference)
        XCTAssertEqual(route, .verifying(reference))
    }

    func test_networkDropAfterSubmission_routesToVerifying() {
        // La requête a pu atteindre le serveur avant la coupure.
        XCTAssertEqual(
            FinancialOutcomeRoute.route(.failed(.networkUnavailable), submittedReference: reference),
            .verifying(reference)
        )
    }

    func test_providerSilenceAfterSubmission_routesToVerifying() {
        XCTAssertEqual(
            FinancialOutcomeRoute.route(.failed(.providerUnavailable), submittedReference: reference),
            .verifying(reference)
        )
    }

    func test_server5xx_isUnknown_but4xx_isEstablishedFailure() {
        XCTAssertTrue(FinancialOutcomeRoute.isFinalityUnknown(.server(statusCode: 500)))
        XCTAssertTrue(FinancialOutcomeRoute.isFinalityUnknown(.server(statusCode: 503)))
        // Code absent : on ne sait pas, donc inconnu — jamais échec par défaut.
        XCTAssertTrue(FinancialOutcomeRoute.isFinalityUnknown(.server(statusCode: nil)))
        XCTAssertFalse(FinancialOutcomeRoute.isFinalityUnknown(.server(statusCode: 400)))
        XCTAssertFalse(FinancialOutcomeRoute.isFinalityUnknown(.server(statusCode: 409)))
    }

    // MARK: - §80 — « Ne jamais transformer Compliance rejection en Network error »

    func test_complianceRejection_staysFailure_notVerifying() {
        let route = FinancialOutcomeRoute.route(.failed(.complianceBlocked(displayReason: nil)),
                                                submittedReference: reference)
        guard case .failed(let error) = route else {
            return XCTFail("Un refus de conformité doit rester un refus, obtenu : \(route)")
        }
        XCTAssertEqual(error, .complianceBlocked(displayReason: nil))
    }

    func test_establishedRefusals_areNeverTreatedAsUnknown() {
        for error: FinanceError in [.duplicate, .conflict, .expired, .unauthorized,
                                    .forbidden, .capabilityUnavailable, .validation(field: nil)] {
            XCTAssertFalse(FinancialOutcomeRoute.isFinalityUnknown(error),
                           "\(error) est un refus établi, pas une issue inconnue")
        }
    }

    // MARK: - Sans référence, pas de réconciliation possible

    func test_unknownOutcomeWithoutReference_cannotBeReconciled_soStaysFailure() {
        // Rien à requêter : l'écran d'échec porte alors le message « ne relancez
        // pas » de `timeoutUnknown`, et non une invitation à repayer.
        guard case .failed(.timeoutUnknown) =
                FinancialOutcomeRoute.route(.failed(.timeoutUnknown), submittedReference: nil) else {
            return XCTFail("Sans référence, l'issue inconnue ne peut pas être vérifiée")
        }
    }

    func test_executed_routesToSubmitted_notConfirmed() {
        // « Soumis » ne dit rien de la finalité : l'état se lit dans le magasin.
        XCTAssertEqual(
            FinancialOutcomeRoute.route(.executed(reference), submittedReference: reference),
            .submitted(reference)
        )
    }

    // MARK: - §78 — l'objet ambigu entre dans la réconciliation

    func test_ambiguousPayload_isPickedUpByReconciliation() {
        let payload = FinancialOutcomeRoute.ambiguousPayload(
            reference: reference, amount: 20_000, currency: "BIF", counterpartyName: "Yohana"
        )
        XCTAssertEqual(payload.status, .unknown)
        XCTAssertTrue(payload.needsReconciliation,
                      "Sans ce drapeau le planificateur ne le reprendrait jamais")
        XCTAssertFalse(payload.canPresentAsSettled,
                       "Un objet ambigu ne doit jamais s'afficher comme réglé")
    }
}
