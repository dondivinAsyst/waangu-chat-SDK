//
//  ChatLaunchContextTests.swift
//  FeatureChatTests
//
//  Contrat d'ouverture du Chat par la Super App — Harness §3, B01.
//  Voir docs/harness/IOS_WORK_PLAN.md (W3).
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class ChatLaunchContextTests: XCTestCase {

    // MARK: - API historique — le paquet est tiré par d'autres projets

    @available(*, deprecated)
    func test_legacyInit_withoutDestination_opensTheInbox() {
        XCTAssertEqual(ChatLaunchContext(source: .tab).route, .chats)
    }

    @available(*, deprecated)
    func test_legacyInit_conversation_mapsToConversationRoute() {
        let launch = ChatLaunchContext(conversationID: "c_1", source: .deepLink)
        XCTAssertEqual(launch.route, .conversation(id: "c_1"))
        XCTAssertEqual(launch.conversationID, "c_1")
    }

    @available(*, deprecated)
    func test_legacyInit_financialReference_mapsToObjectRoute_andIsReturnedUnchanged() {
        let reference = FinancialReference(type: .payment, id: "obj_1", version: 3, correlationID: CorrelationId())
        let launch = ChatLaunchContext(financialReference: reference, source: .push)
        XCTAssertEqual(launch.route, .financialObject(opaqueId: "obj_1", objectType: "PAYMENT"))
        XCTAssertEqual(launch.financialReference, reference, "Version et corrélation rendues telles quelles")
        XCTAssertTrue(launch.designatesFinancialObject)
    }


    /// Push et lien profond viennent de l'extérieur : leur contenu n'est jamais
    /// promu en vérité. Toute autre source est un geste dans l'application.
    func test_onlyPushAndDeepLink_requireServerResolution() {
        let untrusted = ChatEntrySource.allCases.filter(\.requiresServerResolution)
        XCTAssertEqual(Set(untrusted), [.push, .deepLink])
    }

    func test_financialDestinations_areRecognised() {
        let financial: [ChatRoute] = [
            .financialObject(opaqueId: "obj_1", objectType: "PAYMENT_REQUEST"),
            .paymentLink(token: "tok", nonce: "n"),
        ]
        for route in financial {
            XCTAssertTrue(ChatLaunchContext(route: route, source: .push).designatesFinancialObject, "\(route)")
        }

        let ordinary: [ChatRoute] = [
            .chats, .updates, .communities, .calls, .settings, .share,
            .conversation(id: "c_1"), .channel(channelId: "ch_1"), .channelInvite(inviteCode: "ABC"),
        ]
        for route in ordinary {
            XCTAssertFalse(ChatLaunchContext(route: route, source: .tab).designatesFinancialObject, "\(route)")
        }
    }

    /// La provenance fait partie de l'ouverture : la même destination venue
    /// d'un push n'est pas la même ouverture que venue d'un geste.
    func test_sameRouteFromAnotherSource_isAnotherLaunch() {
        let route = ChatRoute.conversation(id: "c_1")
        XCTAssertNotEqual(ChatLaunchContext(route: route, source: .push),
                          ChatLaunchContext(route: route, source: .tab))
    }
}
