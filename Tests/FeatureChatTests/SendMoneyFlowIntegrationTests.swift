//
//  SendMoneyFlowIntegrationTests.swift
//  FeatureChatTests
//
//  Ce qui se passe réellement quand on va au bout d'« Envoyer de l'argent ».
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Exerce `SendMoneyUseCase` de bout en bout avec les mêmes doublures que la
/// simulation de l'application.
///
/// Écrit parce que la question « que se passe-t-il si on confirme ? » ne se
/// répond pas en lisant : le parcours traverse huit gardes, et c'est la
/// première qui refuse qui décide de ce que voit l'utilisateur.
final class SendMoneyFlowIntegrationTests: XCTestCase {

    private static let bif = "BIF"

    private func quote(expiresIn: TimeInterval = 120,
                       compliance: ComplianceState = .approved) -> TransferQuote {
        TransferQuote(
            reference: FinancialReference(type: .payment, id: "tx-1", version: 1,
                                          correlationID: CorrelationId()),
            amount: 25_000, currency: Self.bif,
            feeAmount: 375, feeCurrency: Self.bif,
            totalAmount: 25_375, totalCurrency: Self.bif,
            recipientVerification: .verified,
            complianceState: compliance,
            issuedAt: Date(),
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    private func makeUseCase(
        quoting: any TransferQuoting,
        permits: any ExecutionPermitIssuing,
        client: (any FinanceAPIClientProtocol)?
    ) -> SendMoneyUseCase {
        SendMoneyUseCase(
            quoting: quoting, permits: permits, client: client,
            preserver: nil, logger: SilentLogger()
        )
    }

    private func confirm(
        quoting: any TransferQuoting = EchoQuoting(),
        permits: any ExecutionPermitIssuing = GrantingPermits(),
        client: (any FinanceAPIClientProtocol)? = nil,
        quote q: TransferQuote? = nil
    ) async -> SendMoneyUseCase.Outcome {
        let agreed = q ?? quote()
        return await makeUseCase(quoting: quoting, permits: permits, client: client)
            .confirm(
                agreed: agreed,
                recipientID: "debug-recipient",
                operationID: "op-1",
                idempotency: IdempotencyContext(
                key: "key-1", clientRequestID: UUID(),
                correlationID: CorrelationId(), deviceID: "test-device"
            ),
                attestation: nil
            )
    }

    // MARK: - Ce qui arrive aujourd'hui

    /// **Le cas réel de l'application.** Le permis est délivré par la
    /// simulation, puis le vrai `FinanceAPIClient` tente le réseau — et il n'y a
    /// pas de backend. Ce test fige ce que l'utilisateur obtient à ce moment.
    func test_confirm_withoutBackendClient_reportsCapabilityUnavailable() async {
        let outcome = await confirm(client: nil)

        guard case .failed(let error) = outcome else {
            return XCTFail("Sans client, l'exécution ne peut pas aboutir : \(outcome)")
        }
        XCTAssertEqual(error, .capabilityUnavailable,
                       "Sans backend, le parcours s'arrête proprement — pas un faux succès.")
    }

    /// Un devis périmé est refusé **avant** toute tentative d'exécution.
    func test_expiredQuoteIsRefusedBeforeExecution() async {
        let outcome = await confirm(quote: quote(expiresIn: -1))

        guard case .failed(let error) = outcome else { return XCTFail("attendu : refus") }
        XCTAssertEqual(error, .expired)
    }

    /// Compliance non approuvée : refus, quel que soit l'état du reste.
    func test_complianceBlockStopsExecution() async {
        let outcome = await confirm(quote: quote(compliance: .denied))

        guard case .failed = outcome else { return XCTFail("attendu : refus Compliance") }
    }

    /// Le permis refusé arrête le parcours — c'est ce qui se produisait avant
    /// que `executionPermits` soit injecté.
    func test_refusedPermitStopsExecution() async {
        let outcome = await confirm(permits: RefusingPermits())

        guard case .failed(let error) = outcome else { return XCTFail("attendu : refus") }
        XCTAssertEqual(error, .capabilityUnavailable)
    }

    /// Conditions changées entre l'accord et la confirmation : l'utilisateur
    /// doit revoir un devis, pas subir un débit à un autre montant.
    func test_changedConditionsAskForNewAgreement() async {
        let outcome = await confirm(quoting: DivergingQuoting())

        guard case .needsNewAgreement(let fields, _) = outcome else {
            return XCTFail("attendu : nouvel accord, obtenu \(outcome)")
        }
        XCTAssertTrue(fields.contains(.amount),
                      "Le champ qui a bougé doit être nommé, pas un « réessayez ».")
    }
}

// MARK: - Doublures

/// Rend le devis inchangé — le cas nominal.
private struct EchoQuoting: TransferQuoting {
    func quote(for draft: TransferDraft) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    func refreshQuote(_ quote: TransferQuote) async -> Result<TransferQuote, FinanceError> {
        .success(quote)
    }
}

/// Rend un devis dont le montant a changé.
private struct DivergingQuoting: TransferQuoting {
    func quote(for draft: TransferDraft) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    func refreshQuote(_ quote: TransferQuote) async -> Result<TransferQuote, FinanceError> {
        .success(TransferQuote(
            reference: quote.reference,
            amount: quote.amount + 5_000,
            currency: quote.currency,
            feeAmount: quote.feeAmount, feeCurrency: quote.feeCurrency,
            totalAmount: (quote.totalAmount ?? 0) + 5_000, totalCurrency: quote.totalCurrency,
            recipientVerification: quote.recipientVerification,
            complianceState: quote.complianceState,
            issuedAt: Date(), expiresAt: quote.expiresAt
        ))
    }
}

private struct GrantingPermits: ExecutionPermitIssuing {
    func issue(for snapshot: ConfirmationSnapshot, idempotency: IdempotencyContext,
               stepUp: StepUpAttestation?) async -> Result<ExecutionPermit, FinanceError> {
        .success(ExecutionPermit(
            permitID: "p-1", objectID: snapshot.reference.id,
            snapshotHash: snapshot.decisionHash,
            issuedAt: Date(), expiresAt: Date().addingTimeInterval(180)
        ))
    }
    func consume(_ permit: ExecutionPermit) async -> Result<Void, FinanceError> { .success(()) }
}

private struct RefusingPermits: ExecutionPermitIssuing {
    func issue(for snapshot: ConfirmationSnapshot, idempotency: IdempotencyContext,
               stepUp: StepUpAttestation?) async -> Result<ExecutionPermit, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    func consume(_ permit: ExecutionPermit) async -> Result<Void, FinanceError> { .success(()) }
}
