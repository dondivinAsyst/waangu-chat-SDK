//
//  FinancialDisputeEventTests.swift
//  FeatureChatTests
//
//  Un litige s'ouvre ou se ferme : la carte se relit (réponse du backend, Q11).
//

import XCTest
@testable import WaanguFeatureChat

final class FinancialDisputeEventTests: XCTestCase {

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    func test_disputeOpenedAndClosed_areRecognised() {
        for name in ["conversation.financial.dispute.opened", "conversation.financial.dispute.closed"] {
            let event = ChatMqttEventParser.parse(data: json([
                "eventType": name,
                "payload": ["subject": ["conversationId": "conv_1", "disputeId": "dsp_1"], "conversationId": "conv_1"]
            ]))
            XCTAssertEqual(event?.type, "finance_dispute_changed", name)
            XCTAssertEqual(event?.referenceId, "dsp_1")
            XCTAssertEqual(event?.conversationId, "conv_1")
        }
    }

    /// Sans identifiant de litige, l'événement passe : toutes les cartes de litige se relisent.
    func test_disputeEventWithoutAnID_isStillDelivered() {
        let event = ChatMqttEventParser.parse(data: json(["eventType": "conversation.financial.dispute.closed", "payload": [:]]))
        XCTAssertEqual(event?.type, "finance_dispute_changed")
        XCTAssertNil(event?.referenceId)
    }
}
