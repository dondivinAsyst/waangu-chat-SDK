//
//  ChatLaunchFailureTests.swift
//  FeatureChatTests
//
//  Échec d'ouverture du Chat — Harness §6, §88, B02.
//  Voir docs/harness/IOS_WORK_PLAN.md (W4).
//

import XCTest
@testable import WaanguFeatureChat

final class ChatLaunchFailureTests: XCTestCase {

    private struct DependenciesUnavailable: Error {
        let detail = "https://chat.example/conv_SECRET?token=tok_SECRET"
    }

    /// « Réessayer » rejoue exactement l'ouverture demandée.
    func test_failureKeepsTheRequestedLaunch() {
        let launch = ChatLaunchContext(route: .conversation(id: "c_1"), source: .push)
        XCTAssertEqual(ChatLaunchFailure(launch: launch, error: DependenciesUnavailable()).launch, launch)
    }

    /// La trace dit d'où venait l'ouverture et ce qu'elle visait, jamais quoi
    /// précisément : aucun identifiant de route, aucun message d'erreur.
    func test_logLine_carriesNoIdentifierOrErrorMessage() {
        let routes: [ChatRoute] = [
            .conversation(id: "conv_SECRET"),
            .financialObject(opaqueId: "obj_SECRET", objectType: "PAYMENT_REQUEST"),
            .paymentLink(token: "tok_SECRET", nonce: "nonce_SECRET"),
            .channelInvite(inviteCode: "invite_SECRET"),
            .channel(channelId: "ch_SECRET"),
        ]
        for route in routes {
            let line = ChatLaunchFailure(launch: ChatLaunchContext(route: route, source: .deepLink),
                                         error: DependenciesUnavailable()).logLine
            XCTAssertFalse(line.contains("SECRET"), line)
            XCTAssertFalse(line.contains("PAYMENT_REQUEST"), line)
            XCTAssertTrue(line.contains("source=deepLink"), line)
            XCTAssertTrue(line.contains("destination=\(route.kind)"), line)
            XCTAssertTrue(line.contains("error=DependenciesUnavailable"), line)
        }
    }

    func test_eachFailureIsDistinct_soTheAlertReappearsOnARepeatedFailure() {
        let launch = ChatLaunchContext(route: .chats, source: .tab)
        XCTAssertNotEqual(ChatLaunchFailure(launch: launch, error: DependenciesUnavailable()).id,
                          ChatLaunchFailure(launch: launch, error: DependenciesUnavailable()).id)
    }
}
