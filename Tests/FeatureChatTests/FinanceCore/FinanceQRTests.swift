//
//  FinanceQRTests.swift
//  FeatureChatTests
//
//  §5.2 — lire un QR : une lecture, jamais un paiement.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceQRTests: XCTestCase {

    func test_parse_sendsPayloadAndNonce_andNeverPays() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/qr/parse"] = FinanceCoreJSON.wrap(#"{"merchantId":"m_1"}"#)
        let (services, server) = FinanceRequestMoneyTests.make(routes)

        _ = await services.qrResolver.resolve(payload: "00020101021…", nonce: "n_1")

        let calls = await server.calls
        let parse = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/qr/parse" })
        XCTAssertEqual(parse.body["payload"] as? String, "00020101021…", "La charge brute, telle quelle")
        XCTAssertEqual(parse.body["nonce"] as? String, "n_1", "Le nonce : un rejeu devient CF_043")
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/execute") || $0.route.hasSuffix("/prepare") })
    }

    /// `CF_042` (QR invalide) et `CF_043` (nonce rejoué) sont des refus lisibles.
    func test_invalidQR_andReplayedNonce_areRefusals() async {
        for code in ["CF_042", "CF_043"] {
            var routes = FinanceSendMoneyTests.routes()
            routes["POST /chat-core/financial/qr/parse"] = FinanceCoreJSON.error(code)
            let (services, _) = FinanceRequestMoneyTests.make(routes)

            let result = await services.qrResolver.resolve(payload: "x", nonce: "n")

            guard case .failure = result else { return XCTFail("\(code) doit refuser") }
        }
    }
}
