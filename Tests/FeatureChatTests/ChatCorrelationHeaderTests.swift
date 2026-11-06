//
//  ChatCorrelationHeaderTests.swift
//  FeatureChatTests
//
//  B59 — les requêtes du chat portent un identifiant de corrélation.
//
//  Avant, seules les requêtes financières envoyaient `X-Correlation-Id` : un
//  incident sur la synchronisation, les groupes ou les statuts ne pouvait pas
//  être rapproché entre le client et le serveur. Les en-têtes sont posés par
//  les endpoints du chat, pas par le client réseau partagé : les appels aux
//  facturiers et au wallet restent inchangés.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class ChatCorrelationHeaderTests: XCTestCase {

    private let chatEndpoints: [(String, any APIEndpoint)] = [
        ("conversation sync", ConversationSyncEndpoints.syncConversations(since: nil, limit: 1)),
        ("message sync", ConversationSyncEndpoints.syncConversationMessages(conversationId: "c-1", since: nil, limit: 1)),
        ("stories sync", StatusEndpoints.syncStories(since: nil, limit: 1)),
        ("contact status", StatusEndpoints.getContactStatus),
        ("key bundle", E2EEEndpoints.fetchKeyBundle(userId: "u-1"))
    ]

    func test_chatRequests_carryACorrelationId() {
        for (name, endpoint) in chatEndpoints {
            let value = endpoint.headers?["X-Correlation-Id"]
            XCTAssertFalse(value?.isEmpty ?? true, "\(name) has no X-Correlation-Id")
        }
    }

    /// Une valeur par requête construite, comme pour la finance.
    func test_eachBuiltRequest_getsItsOwnCorrelationId() {
        let first = StatusEndpoints.getContactStatus.headers?["X-Correlation-Id"]
        let second = StatusEndpoints.getContactStatus.headers?["X-Correlation-Id"]
        XCTAssertNotEqual(first, second)
    }
}
