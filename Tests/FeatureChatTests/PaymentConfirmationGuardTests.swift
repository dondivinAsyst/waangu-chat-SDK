//
//  PaymentConfirmationGuardTests.swift
//  FeatureChatTests
//
//  Tâche 2.2 — le garde refuse ce qu'il acceptait auparavant.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit
import WaanguSecurityKit

final class PaymentConfirmationGuardTests: XCTestCase {

    private func confirmation(
        version: Int = 2,
        currentKnown: Int? = 1,
        status: PaymentStatus = .confirmed,
        amount: Decimal = 1000,
        signature: String = String(repeating: "a", count: 64),
        railProof: RailProof? = nil
    ) -> PaymentConfirmation {
        PaymentConfirmation(
            reference: FinanceFixtures.reference(version: version),
            amount: amount,
            currency: "BIF",
            status: status,
            backendSignature: signature,
            idempotencyKey: "key-1",
            railProof: railProof ?? RailProof(
                railProvider: "brb",
                railTransactionId: "rail-1",
                railSignature: String(repeating: "b", count: 64),
                railTimestamp: Date(),
                railStatus: "OK",
                railMetadata: [:]
            ),
            currentKnownVersion: currentKnown
        )
    }

    private func makeGuard(_ verdict: FinancialSignatureVerdict) -> PaymentConfirmationGuard {
        PaymentConfirmationGuard(
            logger: .shared,
            verifier: MockSignatureVerifier(verdict: verdict)
        )
    }

    /// Le défaut d'origine : 64 caractères arbitraires suffisaient à valider.
    /// Ils doivent désormais être rejetés dès que la signature est vérifiable.
    func test_arbitrarySixtyFourCharSignatureIsRejected() async {
        let decision = await makeGuard(.forged).decide(on: confirmation())
        XCTAssertEqual(decision, .rejected(.unverifiedSignature))
    }

    func test_authenticSignatureWithRailProofIsAccepted() async {
        let decision = await makeGuard(.authentic).decide(on: confirmation())
        XCTAssertEqual(decision, .accepted)
    }

    /// Sans clé de vérification, le verdict est indéterminé — jamais accepté,
    /// jamais accusé de falsification.
    func test_unverifiableSignatureIsUndeterminedNotAccepted() async {
        let decision = await makeGuard(.unverifiable(reason: "no_key")).decide(on: confirmation())
        XCTAssertEqual(decision, .undetermined(.backendContractPending))
    }

    /// La fraîcheur est contrôlée **avant** la signature : une confirmation
    /// authentiquement signée mais périmée est un rejeu.
    func test_staleVersionRejectedEvenWithValidSignature() async {
        let decision = await makeGuard(.authentic)
            .decide(on: confirmation(version: 1, currentKnown: 5))
        XCTAssertEqual(decision, .rejected(.staleVersion(incoming: 1, current: 5)))
    }

    /// Même version : rejeu, donc rejet.
    func test_equalVersionIsRejected() async {
        let decision = await makeGuard(.authentic)
            .decide(on: confirmation(version: 3, currentKnown: 3))
        XCTAssertEqual(decision, .rejected(.staleVersion(incoming: 3, current: 3)))
    }

    func test_nonPositiveAmountIsRejected() async {
        let decision = await makeGuard(.authentic).decide(on: confirmation(amount: 0))
        XCTAssertEqual(decision, .rejected(.nonPositiveAmount))
    }

    func test_nonFinalStatusIsRejected() async {
        let decision = await makeGuard(.authentic).decide(on: confirmation(status: .processing))
        XCTAssertEqual(decision, .rejected(.statusNotFinal(.processing)))
    }

    func test_emptySignatureIsRejected() async {
        let decision = await makeGuard(.authentic).decide(on: confirmation(signature: ""))
        XCTAssertEqual(decision, .rejected(.missingSignature))
    }

    /// Preuve de rail absente : indéterminé, pas rejeté. Le backend a bien signé ;
    /// le rail n'a simplement pas encore rendu sa preuve.
    func test_missingRailProofIsUndetermined() async {
        let empty = RailProof(
            railProvider: "", railTransactionId: "", railSignature: "",
            railTimestamp: Date(), railStatus: "", railMetadata: [:]
        )
        let decision = await makeGuard(.authentic).decide(on: confirmation(railProof: empty))
        XCTAssertEqual(decision, .undetermined(.missingRailProof))
    }

    /// Un premier contact — aucune révision connue — ne doit pas être pris pour
    /// un rejeu.
    func test_firstContactIsNotTreatedAsStale() async {
        let decision = await makeGuard(.authentic)
            .decide(on: confirmation(version: 1, currentKnown: nil))
        XCTAssertEqual(decision, .accepted)
    }
}
