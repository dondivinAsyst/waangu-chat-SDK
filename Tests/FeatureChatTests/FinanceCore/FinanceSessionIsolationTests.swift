//
//  FinanceSessionIsolationTests.swift
//  FeatureChatTests
//
//  Changement de compte et session invalidée par le serveur — §1.5–1.6, Bloc 1 §2.5.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceSessionIsolationTests: XCTestCase {

    /// Un devis préparé et un jeton appris pour le compte A ne servent jamais au compte B.
    func test_invalidate_forgetsPreparedQuotesAndBeneficiaries() async throws {
        let (services, server) = FinanceRequestMoneyTests.make()
        _ = try await services.recipientResolver.resolve(.phoneNumber("+257"), knownAs: nil).get()
        let quote = try await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft()).get()

        await services.session.invalidate()

        let outcome = await FinanceSendMoneyTests.confirm(quote, services: services)
        XCTAssertNotEqual(outcome, .executed(quote.reference), "Un devis du compte précédent n'est plus confirmable")
        let request = await services.moneyRequests.createRequest(FinanceRequestMoneyTests.draft(amount: 100),
                                                                 idempotency: FinanceFixtures.idempotency())
        guard case .failure(.recipientUnresolved) = request else { return XCTFail("\(request)") }

        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/send-money/execute") })
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/request-money") })
    }

    /// CF_066 : la session doit être reprise — l'instantané en cache est oublié.
    func test_resumeRequiredCode_forcesANewBootstrap() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/send-money/prepare"] = FinanceCoreJSON.error("CF_066")
        let (services, server) = FinanceSendMoneyTests.make(routes)

        _ = await services.session.status()
        _ = await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft())
        _ = await services.session.status()

        let bootstraps = await server.calls.filter { $0.route == "GET /chat-core/governance/capabilities" }.count
        XCTAssertEqual(bootstraps, 2)
    }

    /// Un refus métier ordinaire ne relance pas l'amorçage.
    func test_ordinaryBusinessCode_keepsTheSession() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/send-money/prepare"] = FinanceCoreJSON.error("CF_029")
        let (services, server) = FinanceSendMoneyTests.make(routes)

        _ = await services.session.status()
        _ = await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft())
        _ = await services.session.status()

        let bootstraps = await server.calls.filter { $0.route == "GET /chat-core/governance/capabilities" }.count
        XCTAssertEqual(bootstraps, 1)
    }
}
