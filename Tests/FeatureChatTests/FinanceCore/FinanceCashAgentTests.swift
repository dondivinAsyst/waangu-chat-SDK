//
//  FinanceCashAgentTests.swift
//  FeatureChatTests
//
//  §6 — dépôt chez un agent, et la frontière `CF_038`.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceCashAgentTests: XCTestCase {

    // MARK: - Les routes

    func test_routes_matchTheContract() {
        let verify = ChatFinanceEndpoints.verifyAgent(
            CashAgentRequest(financialIntentRef: "fco_1", conversationId: "c1", agentId: "a1"))
        let confirm = ChatFinanceEndpoints.confirmPhysical(
            CashRefRequest(financialIntentRef: "fco_1", conversationId: "c1"))

        XCTAssertEqual(verify.path, "/chat-core/financial/cash-in/verify-agent")
        XCTAssertEqual(confirm.path, "/chat-core/financial/cash-in/confirm-physical")
        XCTAssertEqual(verify.method, .post)
        XCTAssertEqual(confirm.method, .post)
    }

    // MARK: - CF_038 : physique confirmé ≠ crédit

    /// **L'invariant du §6.** L'agent a pris les billets, le serveur laisse
    /// `creditState: PENDING` : l'argent n'est pas au compte, et rien dans le
    /// modèle ne doit permettre de dire le contraire.
    func test_physicalReceived_isNotACredit() throws {
        let overlay = try Self.overlay("""
        {"financialIntentRef":"fco_1","conversationId":"c1","channel":"AGENT","agentId":"a1",
         "agentVerified":true,"physicalReceivedAt":"2026-09-25T12:10:00Z",
         "financeRef":null,"creditState":"PENDING"}
        """)

        XCTAssertNotNil(overlay.physicalReceivedAt)
        XCTAssertFalse(overlay.isCredited, "PENDING n'est pas un crédit")
        XCTAssertTrue(overlay.awaitsCredit, "L'écran doit montrer l'attente, ni succès ni échec")
    }

    /// Un état que ce client ne connaît pas **n'est pas** un crédit : la liste
    /// des états créditeurs est fermée, et le doute se lit « pas encore ».
    func test_unknownCreditState_isNeverACredit() throws {
        let overlay = try Self.overlay("""
        {"financialIntentRef":"fco_1","agentVerified":true,
         "physicalReceivedAt":"2026-09-25T12:10:00Z","creditState":"SOMETHING_NEW"}
        """)

        XCTAssertFalse(overlay.isCredited)
        XCTAssertTrue(overlay.awaitsCredit)
    }

    /// Le crédit ne se déduit **jamais** de la réception physique : sans état
    /// créditeur, il n'y a pas de crédit, même agent vérifié et espèces reçues.
    func test_creditIsNeverInferred() {
        let overlay = CashInAgentOverlay(
            reference: Self.reference, agentVerified: true,
            physicalReceivedAt: Date(), creditState: "")

        XCTAssertFalse(overlay.isCredited)
    }

    /// Quand le serveur l'affirme, le crédit est acquis.
    func test_creditedState_isACredit() throws {
        for state in ["CREDITED", "COMPLETED", "SETTLED", "credited"] {
            let overlay = try Self.overlay("""
            {"financialIntentRef":"fco_1","physicalReceivedAt":"2026-09-25T12:10:00Z",
             "creditState":"\(state)"}
            """)
            XCTAssertTrue(overlay.isCredited, state)
            XCTAssertFalse(overlay.awaitsCredit, state)
        }
    }

    // MARK: - Vérification de l'agent

    /// Vérifier l'agent n'est pas déposer : aucune espèce reçue à ce stade.
    func test_verifiedAgent_hasReceivedNothingYet() throws {
        let overlay = try Self.overlay("""
        {"financialIntentRef":"fco_1","conversationId":"c1","channel":"AGENT","agentId":"a1",
         "agentVerified":true,"physicalReceivedAt":null,"financeRef":null,"creditState":"PENDING"}
        """)

        XCTAssertTrue(overlay.agentVerified)
        XCTAssertNil(overlay.physicalReceivedAt)
        XCTAssertFalse(overlay.awaitsCredit, "Rien n'a encore été remis")
        XCTAssertEqual(overlay.channel, .agent)
        XCTAssertEqual(overlay.agentID, "a1")
    }

    /// Une charge sans le moindre champ optionnel reste lisible, et ne crédite
    /// rien.
    func test_sparseOverlay_readsClosed() throws {
        let overlay = try Self.overlay("{\"financialIntentRef\":\"fco_1\"}")

        XCTAssertFalse(overlay.agentVerified)
        XCTAssertFalse(overlay.isCredited)
        XCTAssertNil(overlay.channel)
    }

    // MARK: - Aides

    private static let reference = FinancialReference(
        type: .cashIn, id: "fco_1", version: 1, correlationID: CorrelationId())

    private static func overlay(_ json: String) throws -> CashInAgentOverlay {
        let dto = try JSONDecoder().decode(CashInOverlayDTO.self, from: Data(json.utf8))
        return CashChannelMapper.overlay(dto, reference: reference)
    }
}
