//
//  PaymentStatusMappingTests.swift
//  FeatureChatTests
//
//  Tâche 10.2 — un statut inconnu ne devient jamais un échec.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class PaymentStatusMappingTests: XCTestCase {

    private func decode(_ raw: String) throws -> PaymentStatus {
        let json = Data("\"\(raw)\"".utf8)
        return try JSONDecoder().decode(PaymentStatus.self, from: json)
    }

    // MARK: - Décodage défensif

    /// Le cœur du §3.1 : un statut que ce client ignore devient `.unknown`.
    /// S'il devenait `.failed`, l'utilisateur serait invité à repayer une
    /// opération peut-être aboutie.
    func test_unknownRawValueDecodesToUnknown() throws {
        XCTAssertEqual(try decode("SOME_FUTURE_STATUS"), .unknown)
        XCTAssertNotEqual(try decode("SOME_FUTURE_STATUS"), .failed)
    }

    func test_knownRawValuesDecodeExactly() throws {
        XCTAssertEqual(try decode("CONFIRMED"), .confirmed)
        XCTAssertEqual(try decode("PENDING_SETTLEMENT"), .pendingSettlement)
        XCTAssertEqual(try decode("UNKNOWN"), .unknown)
    }

    /// Un statut inconnu ne doit pas faire échouer le décodage de l'objet entier :
    /// la carte deviendrait illisible au lieu d'être imprécise.
    func test_decodingNeverThrowsOnUnknownStatus() {
        XCTAssertNoThrow(try decode("💥"))
    }

    // MARK: - Sémantique

    /// `unknown` n'appartient à aucune des deux catégories du raisonnement binaire
    /// abouti/en-cours — c'est ce qui empêche de le traiter comme l'un ou l'autre.
    func test_unknownIsNeitherInFlightNorTerminal() {
        XCTAssertFalse(PaymentStatus.unknown.isInFlight)
        XCTAssertFalse(PaymentStatus.unknown.isTerminal)
        XCTAssertTrue(PaymentStatus.unknown.requiresReconciliation)
    }

    /// Retenter une opération dont l'issue est inconnue est le chemin du double débit.
    func test_unknownForbidsUserRetry() {
        XCTAssertFalse(PaymentStatus.unknown.allowsUserRetry)
        XCTAssertTrue(PaymentStatus.failed.allowsUserRetry)
        XCTAssertTrue(PaymentStatus.expired.allowsUserRetry)
    }

    func test_pendingSettlementCountsAsDebited() {
        // L'utilisateur a été débité même si le règlement interbancaire suit.
        XCTAssertTrue(PaymentStatus.pendingSettlement.isDebitVisibleToUser)
        XCTAssertFalse(PaymentStatus.pending.isDebitVisibleToUser)
    }

    /// Chaque statut doit produire un traitement d'affichage, sinon un ajout
    /// futur laisserait la carte sans rien à montrer.
    ///
    /// Les libellés ne sont plus interrogeables depuis un statut : ils vivent sur
    /// `FinancialCardPresentation` et sont privés à la vue. C'est le tour de vis
    /// qui empêche une carte de rendre un statut sans passer par la vérification.
    func test_everyStatusMapsToAPresentation() {
        for status in PaymentStatus.allCases {
            let mapped = FinancialCardPayloadFixture.make(
                status: status,
                verification: .verified
            ).presentation
            XCTAssertNotEqual(
                mapped, .repudiated,
                "\(status) vérifié ne peut pas être répudié"
            )
        }
    }

    /// `unknown` ne doit jamais s'annoncer comme un échec — ni comme un succès.
    func test_unknownPresentsAsVerifying() {
        for verification in [FinancialCardVerification.verified, .unverified] {
            XCTAssertEqual(
                FinancialCardPayloadFixture.make(status: .unknown, verification: verification).presentation,
                .verifying
            )
        }
    }
}
