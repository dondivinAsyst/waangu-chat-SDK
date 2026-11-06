//
//  FinanceErrorSemanticsTests.swift
//  FeatureChatTests
//
//  Tâches 10.6, 10.7 — le timeout après soumission n'est jamais un échec.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinanceErrorSemanticsTests: XCTestCase {

    // MARK: - Traduction depuis AppError

    /// Le même timeout n'a pas le même sens avant et après soumission.
    /// C'est toute la différence entre « réessayez » et « ne relancez pas ».
    func test_timeoutMeaningDependsOnSubmission() {
        XCTAssertEqual(FinanceError.from(.timeout, afterSubmission: false), .networkUnavailable)
        XCTAssertEqual(FinanceError.from(.timeout, afterSubmission: true), .timeoutUnknown)
    }

    /// Une réponse illisible après soumission ne prouve rien sur l'état de
    /// l'opération : c'est une ambiguïté, pas une erreur de parsing.
    func test_decodingErrorAfterSubmissionIsAmbiguous() {
        XCTAssertEqual(
            FinanceError.from(.decodingError("bad"), afterSubmission: true),
            .timeoutUnknown
        )
    }

    func test_authErrorsMapToUnauthorized() {
        XCTAssertEqual(FinanceError.from(.sessionExpired, afterSubmission: true), .unauthorized)
        XCTAssertEqual(FinanceError.from(.tokenRefreshFailed, afterSubmission: false), .unauthorized)
    }

    // MARK: - Politique de reprise

    /// Le point le plus important du fichier : retenter une opération dont
    /// l'issue est inconnue est le chemin du double débit.
    func test_timeoutUnknownIsNeverSafeToRetry() {
        XCTAssertFalse(FinanceError.timeoutUnknown.isSafeToRetry)
        XCTAssertTrue(FinanceError.timeoutUnknown.requiresReconciliation)
    }

    /// Une opération déjà enregistrée doit être relue, pas refaite.
    func test_duplicateIsNotRetryable() {
        XCTAssertFalse(FinanceError.duplicate.isSafeToRetry)
        XCTAssertTrue(FinanceError.duplicate.requiresReconciliation)
    }

    func test_transientInfrastructureErrorsAreRetryable() {
        XCTAssertTrue(FinanceError.networkUnavailable.isSafeToRetry)
        XCTAssertTrue(FinanceError.providerUnavailable.isSafeToRetry)
        XCTAssertTrue(FinanceError.server(statusCode: 503).isSafeToRetry)
    }

    // MARK: - Présentation

    /// Une erreur ambiguë s'affiche en `unknown`, jamais en `failed`.
    func test_ambiguousErrorDisplaysAsUnknown() {
        XCTAssertEqual(FinanceError.timeoutUnknown.displayedStatus, .unknown)
        XCTAssertEqual(FinanceError.conflict.displayedStatus, .unknown)
    }

    /// Aucun message utilisateur ne doit exposer de code technique.
    func test_userMessagesLeakNoTechnicalDetail() {
        let errors: [FinanceError] = [
            .unauthorized, .forbidden, .complianceBlocked(displayReason: nil),
            .capabilityUnavailable, .expired, .duplicate, .conflict,
            .timeoutUnknown, .networkUnavailable, .providerUnavailable,
            .validation(field: nil), .server(statusCode: 500)
        ]
        for error in errors {
            XCTAssertFalse(error.userMessage.isEmpty, "\(error) sans message")
            XCTAssertFalse(error.userMessage.contains("500"), "\(error) expose un code HTTP")
            XCTAssertFalse(error.userMessage.lowercased().contains("error"), "\(error) expose un terme technique")
        }
    }

    /// Le message de `timeoutUnknown` ne doit pas annoncer un échec — ce serait
    /// une invitation à repayer.
    func test_timeoutMessageDoesNotClaimFailure() {
        let message = FinanceError.timeoutUnknown.userMessage.lowercased()
        XCTAssertFalse(message.contains("échou"))
        XCTAssertFalse(message.contains("erreur"))
    }
}
