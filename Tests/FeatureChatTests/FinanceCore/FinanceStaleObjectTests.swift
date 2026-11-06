//
//  FinanceStaleObjectTests.swift
//  FeatureChatTests
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Objets que le serveur ne connaît pas (`CF_011`), et reprise après déverrouillage.
final class FinanceStaleObjectTests: XCTestCase {

    func test_CF011_isRecognisable() {
        XCTAssertEqual(FinanceCoreErrorCode(rawValue: "CF_011").financeError, .financialObjectNotFound)
    }

    /// Une inscription que le serveur dit inconnue est oubliée : plus relue à
    /// chaque réconciliation.
    func test_objectUnknownToServer_isForgotten() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["GET /chat-core/financial/objects/ghost"] = FinanceCoreJSON.error("CF_011")
        let (services, _) = FinanceRequestMoneyTests.make(routes)
        let store = FinancialObjectStore()
        let useCases = FinancialObjectUseCases(
            store: store, client: services.apiClient, guardian: services.confirmationGuard,
            capabilities: MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities), logger: SilentLogger())
        let reference = FinanceFixtures.reference(id: "ghost", version: 0)
        await useCases.recordSubmission(FinancialOutcomeRoute.ambiguousPayload(
            reference: reference, amount: 500_000, currency: "BIF", counterpartyName: nil))
        let before = await useCases.pendingReconciliation()
        XCTAssertFalse(before.isEmpty)

        let result = await useCases.refresh(reference)

        XCTAssertEqual(result.failureValueForTest, .financialObjectNotFound)
        let pending = await useCases.pendingReconciliation()
        XCTAssertTrue(pending.isEmpty, "Plus rien à réconcilier")
        let current = await store.current(for: reference)
        XCTAssertNil(current)
    }

    /// La reprise n'a lieu que pour le refus avant envoi, et si la session le permet.
    func test_retryOnlyForThePreSendRefusal_whenTheSessionNowAllowsIt() async {
        let (services, _) = FinanceRequestMoneyTests.make()
        let session = services.session
        let unlocked = await FinanceConfirmRetry.sessionNowAllowsConfirm(after: .capabilityUnavailable,
                                                                          session: session)
        XCTAssertTrue(unlocked)
        let other = await FinanceConfirmRetry.sessionNowAllowsConfirm(after: .timeoutUnknown, session: session)
        XCTAssertFalse(other, "Issue inconnue : jamais reconfirmé")
        let noSession = await FinanceConfirmRetry.sessionNowAllowsConfirm(after: .capabilityUnavailable, session: nil)
        XCTAssertFalse(noSession)
    }
}

private extension Result {
    var failureValueForTest: Failure? { if case .failure(let error) = self { return error }; return nil }
}
