//
//  Bloc10QuoteLifecycleTests.swift
//  FeatureChatTests
//
//  Bloc 10, chapitre 80 §8 — valide → expire bientôt → expiré → actualisation.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class Bloc10QuoteLifecycleTests: XCTestCase {

    private let expiry = Date(timeIntervalSince1970: 1_000_000)

    func test_farFromExpiry_isValid() {
        XCTAssertEqual(QuoteValidity.at(expiry.addingTimeInterval(-120), expiresAt: expiry), .valid)
        XCTAssertEqual(QuoteValidity.at(expiry.addingTimeInterval(-30.5), expiresAt: expiry), .valid)
    }

    func test_withinThreshold_isExpiring_withSecondsRoundedUp() {
        XCTAssertEqual(QuoteValidity.at(expiry.addingTimeInterval(-30), expiresAt: expiry), .expiring(secondsLeft: 30))
        // 0,2 s restantes s'affichent « 1 s », jamais « 0 s » pour un devis encore valable.
        XCTAssertEqual(QuoteValidity.at(expiry.addingTimeInterval(-0.2), expiresAt: expiry), .expiring(secondsLeft: 1))
    }

    func test_atOrPastExpiry_isExpired() {
        XCTAssertEqual(QuoteValidity.at(expiry, expiresAt: expiry), .expired)
        XCTAssertEqual(QuoteValidity.at(expiry.addingTimeInterval(5), expiresAt: expiry), .expired)
    }

    func test_onlyExpiredForbidsConfirmation() {
        XCTAssertTrue(QuoteValidity.valid.allowsConfirmation)
        XCTAssertTrue(QuoteValidity.expiring(secondsLeft: 3).allowsConfirmation)
        XCTAssertFalse(QuoteValidity.expired.allowsConfirmation)
    }

    /// **Expiration pendant l'authentification.** Le devis était valide à la
    /// revue ; il ne l'est plus quand la confirmation part. Rien ne doit être
    /// exécuté, et l'issue doit être `.expired` — que l'écran traduit en devis à
    /// renouveler, pas en échec.
    func test_quoteExpiringDuringAuthentication_isRefused_andNothingExecutes() async {
        let client = MockFinanceAPIClient()
        let quote = TransferQuote(
            reference: FinanceFixtures.reference(id: "tx-9"),
            amount: 10_000, currency: "BIF",
            recipientVerification: .verified, complianceState: .approved,
            issuedAt: Date().addingTimeInterval(-120),
            expiresAt: Date().addingTimeInterval(-1)
        )
        let useCase = SendMoneyUseCase(quoting: StableQuoting(), permits: GrantAll(),
                                       client: client, preserver: nil, logger: SilentLogger())

        let outcome = await useCase.confirm(agreed: quote, recipientID: "r", operationID: "op",
                                            idempotency: FinanceFixtures.idempotency(), attestation: nil)

        XCTAssertEqual(outcome, .failed(.expired))
        let confirms = await client.callCount(for: "confirm")
        XCTAssertEqual(confirms, 0, "Un devis expiré ne part jamais silencieusement")
    }

    /// **Changement de frais pendant l'affichage.** Le rafraîchissement serveur
    /// rend d'autres frais : nouvel accord requis, aucune exécution.
    func test_feeChangeWhileDisplayed_requiresNewAgreement() async {
        let client = MockFinanceAPIClient()
        let quote = TransferQuote(
            reference: FinanceFixtures.reference(id: "tx-10"),
            amount: 10_000, currency: "BIF", feeAmount: 100, feeCurrency: "BIF",
            totalAmount: 10_100, totalCurrency: "BIF",
            recipientVerification: .verified, complianceState: .approved,
            issuedAt: Date(), expiresAt: Date().addingTimeInterval(120)
        )
        let useCase = SendMoneyUseCase(quoting: RaisedFeeQuoting(), permits: GrantAll(),
                                       client: client, preserver: nil, logger: SilentLogger())

        let outcome = await useCase.confirm(agreed: quote, recipientID: "r", operationID: "op",
                                            idempotency: FinanceFixtures.idempotency(), attestation: nil)

        guard case .needsNewAgreement(let fields, _) = outcome else {
            return XCTFail("Des frais modifiés exigent un nouvel accord : \(outcome)")
        }
        XCTAssertFalse(fields.isEmpty)
        let confirms = await client.callCount(for: "confirm")
        XCTAssertEqual(confirms, 0)
    }
}

// MARK: - Doublures

private struct StableQuoting: TransferQuoting {
    func quote(for draft: TransferDraft) async -> Result<TransferQuote, FinanceError> { .failure(.capabilityUnavailable) }
    func refreshQuote(_ quote: TransferQuote) async -> Result<TransferQuote, FinanceError> { .success(quote) }
}

private struct RaisedFeeQuoting: TransferQuoting {
    func quote(for draft: TransferDraft) async -> Result<TransferQuote, FinanceError> { .failure(.capabilityUnavailable) }
    func refreshQuote(_ quote: TransferQuote) async -> Result<TransferQuote, FinanceError> {
        .success(TransferQuote(
            reference: quote.reference, amount: quote.amount, currency: quote.currency,
            feeAmount: (quote.feeAmount ?? 0) + 400, feeCurrency: quote.feeCurrency,
            totalAmount: (quote.totalAmount ?? quote.amount) + 400, totalCurrency: quote.totalCurrency,
            recipientVerification: quote.recipientVerification, complianceState: quote.complianceState,
            issuedAt: Date(), expiresAt: quote.expiresAt
        ))
    }
}

private struct GrantAll: ExecutionPermitIssuing {
    func issue(for snapshot: ConfirmationSnapshot, idempotency: IdempotencyContext,
               stepUp: StepUpAttestation?) async -> Result<ExecutionPermit, FinanceError> {
        .success(ExecutionPermit(permitID: "p", objectID: snapshot.reference.id,
                                 snapshotHash: snapshot.decisionHash,
                                 issuedAt: Date(), expiresAt: Date().addingTimeInterval(180)))
    }
    func consume(_ permit: ExecutionPermit) async -> Result<Void, FinanceError> { .success(()) }
}
