//
//  SendMoneyConfirmationTests.swift
//  FeatureChatTests
//
//  Chapitre 18.4 — la séquence de confirmation, et les scénarios 13 à 16.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

// MARK: - Doublures

actor MockTransferQuoting: TransferQuoting {
    private var refreshed: Result<TransferQuote, FinanceError>
    private(set) var refreshCount = 0

    init(refreshed: Result<TransferQuote, FinanceError>) { self.refreshed = refreshed }
    func setRefreshed(_ v: Result<TransferQuote, FinanceError>) { refreshed = v }

    func quote(for draft: TransferDraft) async -> Result<TransferQuote, FinanceError> { refreshed }
    func refreshQuote(_ quote: TransferQuote) async -> Result<TransferQuote, FinanceError> {
        refreshCount += 1
        return refreshed
    }
}

actor MockPermitIssuer: ExecutionPermitIssuing {
    private(set) var issueCount = 0
    private(set) var consumeCount = 0
    private var honourSnapshot: Bool

    init(honourSnapshot: Bool = true) { self.honourSnapshot = honourSnapshot }

    func issue(
        for snapshot: ConfirmationSnapshot,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<ExecutionPermit, FinanceError> {
        issueCount += 1
        return .success(ExecutionPermit(
            permitID: "permit-1",
            objectID: snapshot.reference.id,
            snapshotHash: honourSnapshot ? snapshot.decisionHash : "autre-empreinte",
            issuedAt: Date(),
            expiresAt: Date().addingTimeInterval(300)
        ))
    }

    func consume(_ permit: ExecutionPermit) async -> Result<Void, FinanceError> {
        consumeCount += 1
        return .success(())
    }
}

private enum QuoteFixtures {
    static func make(
        amount: Decimal = 5_000,
        fee: Decimal? = 25,
        rate: Decimal? = nil,
        verification: VerificationStatus = .verified,
        compliance: ComplianceState = .approved,
        expiresIn: TimeInterval = 300
    ) -> TransferQuote {
        TransferQuote(
            reference: FinanceFixtures.reference(version: 2),
            amount: amount,
            currency: "BIF",
            feeAmount: fee,
            feeCurrency: "BIF",
            taxAmount: nil,
            exchangeRate: rate,
            totalAmount: nil,
            totalCurrency: nil,
            recipientVerification: verification,
            complianceState: compliance,
            issuedAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }
}

// MARK: - Péremption

final class TransferQuoteExpiryTests: XCTestCase {

    /// **Le défaut du Bloc 1 refermé.** `expiresAt` est non optionnel : le
    /// contrôle peut enfin se déclencher, au lieu de retourner toujours `false`.
    func test_expiryIsMandatoryAndActuallyFires() {
        XCTAssertTrue(QuoteFixtures.make(expiresIn: -1).isExpired())
        XCTAssertFalse(QuoteFixtures.make(expiresIn: 300).isExpired())
    }

    func test_remainingValidityNeverGoesNegative() {
        XCTAssertEqual(QuoteFixtures.make(expiresIn: -500).remainingValidity(), 0)
    }
}

// MARK: - Séquence de confirmation

final class SendMoneyConfirmationTests: XCTestCase {

    private func makeUseCase(
        quoting: MockTransferQuoting,
        permits: MockPermitIssuer = MockPermitIssuer(),
        client: MockFinanceAPIClient? = nil
    ) -> SendMoneyUseCase {
        SendMoneyUseCase(
            quoting: quoting,
            permits: permits,
            client: client,
            preserver: MockIdempotencyPreserver(),
            logger: SilentLogger()
        )
    }

    private func confirm(
        _ useCase: SendMoneyUseCase,
        agreed: TransferQuote
    ) async -> SendMoneyUseCase.Outcome {
        await useCase.confirm(
            agreed: agreed,
            recipientID: "rcpt-1",
            operationID: "op-1",
            idempotency: FinanceFixtures.idempotency(),
            attestation: nil
        )
    }

    /// Un devis périmé n'atteint jamais le réseau.
    func test_expiredQuoteIsRefusedBeforeAnyNetworkCall() async {
        let quoting = MockTransferQuoting(refreshed: .success(QuoteFixtures.make()))
        let outcome = await confirm(makeUseCase(quoting: quoting), agreed: QuoteFixtures.make(expiresIn: -1))

        XCTAssertEqual(outcome, .failed(.expired))
        let refreshes = await quoting.refreshCount
        XCTAssertEqual(refreshes, 0, "rien ne part pour un devis mort")
    }

    /// Scénario 14 — frais modifiés entre l'aperçu et la confirmation.
    func test_feeChangeStopsExecution() async {
        let agreed = QuoteFixtures.make(fee: 25)
        let quoting = MockTransferQuoting(refreshed: .success(QuoteFixtures.make(fee: 900)))
        let permits = MockPermitIssuer()

        let outcome = await confirm(makeUseCase(quoting: quoting, permits: permits), agreed: agreed)

        guard case .needsNewAgreement(let fields, _) = outcome else {
            return XCTFail("doit exiger un nouvel accord, obtenu \(outcome)")
        }
        XCTAssertEqual(fields, [.fee])

        let issued = await permits.issueCount
        XCTAssertEqual(issued, 0, "aucun permis n'est demandé pour des conditions périmées")
    }

    /// Scénario 15 — taux de change modifié.
    func test_exchangeRateChangeStopsExecution() async {
        let quoting = MockTransferQuoting(refreshed: .success(QuoteFixtures.make(rate: 1.4)))
        let outcome = await confirm(makeUseCase(quoting: quoting), agreed: QuoteFixtures.make(rate: 1.0))

        guard case .needsNewAgreement(let fields, _) = outcome else { return XCTFail("attendu") }
        XCTAssertEqual(fields, [.exchangeRate])
    }

    /// Scénario 13 — la vérification du bénéficiaire se dégrade.
    func test_recipientVerificationDowngradeStopsExecution() async {
        let quoting = MockTransferQuoting(refreshed: .success(QuoteFixtures.make(verification: .revoked)))
        let outcome = await confirm(makeUseCase(quoting: quoting), agreed: QuoteFixtures.make(verification: .verified))

        guard case .needsNewAgreement(let fields, _) = outcome else { return XCTFail("attendu") }
        XCTAssertEqual(fields, [.recipientVerification])
    }

    /// Scénario 16 — la conformité passe de `approved` à `approvalRequired`.
    func test_complianceChangeStopsExecution() async {
        let quoting = MockTransferQuoting(refreshed: .success(QuoteFixtures.make(compliance: .approvalRequired)))
        let outcome = await confirm(makeUseCase(quoting: quoting), agreed: QuoteFixtures.make(compliance: .approved))

        guard case .needsNewAgreement(let fields, _) = outcome else { return XCTFail("attendu") }
        XCTAssertEqual(fields, [.compliance])
    }

    /// La conformité est vérifiée sur l'état **rafraîchi**, pas sur l'aperçu :
    /// un aperçu approuvé ne doit pas ouvrir un blocage survenu depuis.
    func test_blockedComplianceRefusesEvenWhenNothingElseChanged() async {
        let blocked = QuoteFixtures.make(compliance: .blocked)
        let quoting = MockTransferQuoting(refreshed: .success(blocked))
        let outcome = await confirm(makeUseCase(quoting: quoting), agreed: blocked)

        XCTAssertEqual(outcome, .failed(.complianceBlocked(displayReason: nil)))
    }

    /// Un permis qui n'autorise pas l'aperçu pour lequel il vient d'être demandé
    /// est une incohérence backend — l'exécution s'arrête.
    func test_permitNotMatchingTheSnapshotStopsExecution() async {
        let quote = QuoteFixtures.make()
        let quoting = MockTransferQuoting(refreshed: .success(quote))
        let permits = MockPermitIssuer(honourSnapshot: false)

        let outcome = await confirm(makeUseCase(quoting: quoting, permits: permits), agreed: quote)
        XCTAssertEqual(outcome, .failed(.executionPermitExpired))
    }

    /// Sans client financier, rien ne s'exécute — et ce n'est pas un échec de
    /// paiement.
    func test_missingClientIsCapabilityNotFailure() async {
        let quote = QuoteFixtures.make()
        let quoting = MockTransferQuoting(refreshed: .success(quote))
        let outcome = await confirm(makeUseCase(quoting: quoting, client: nil), agreed: quote)

        XCTAssertEqual(outcome, .failed(.capabilityUnavailable))
    }
}

// MARK: - Fermé par défaut

final class ClosedTransferQuotingTests: XCTestCase {

    /// Le client ne peut pas fabriquer un devis : il faudrait inventer des frais
    /// et un taux — le calcul financier local que l'architecture interdit.
    func test_closedQuotingProducesNothing() async {
        let draft = TransferDraft(recipientID: "r", amount: 1_000, currency: "BIF")
        let result = await ClosedTransferQuoting().quote(for: draft)
        guard case .failure(let error) = result else { return XCTFail("doit refuser") }
        XCTAssertEqual(error, .capabilityUnavailable)
    }
}
