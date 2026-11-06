//
//  ChatModuleTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 1.10 — quelles parties du Chat l'hôte demande, et ce que cela retire.
//

import XCTest
@testable import WaanguFeatureChat

final class ChatModuleTests: XCTestCase {

    func test_standard_isEverythingButPayments() {
        XCTAssertEqual(ChatModule.standard, [.calls, .status, .communities])
        XCTAssertFalse(ChatModule.standard.contains(.payments))
    }

    /// Un appelant qui ne dit rien garde le comportement d'avant : tout.
    func test_all_isEveryModule() {
        XCTAssertEqual(ChatModule.all, Set(ChatModule.allCases))
        XCTAssertEqual(ChatModule.allCases.count, 4)
    }

    // MARK: Onglets

    func test_eachOptionalTab_followsItsModule() {
        XCTAssertEqual(Tab.updates.module, .status)
        XCTAssertEqual(Tab.calls.module, .calls)
        XCTAssertEqual(Tab.communities.module, .communities)
    }

    func test_chatsAndSettings_areAlwaysThere() {
        XCTAssertNil(Tab.chats.module)
        XCTAssertNil(Tab.settings.module)
        XCTAssertTrue(Tab.chats.isEnabled(in: []))
        XCTAssertTrue(Tab.settings.isEnabled(in: []))
    }

    func test_aTabIsOnlyThereWithItsModule() {
        XCTAssertTrue(Tab.calls.isEnabled(in: [.calls]))
        XCTAssertFalse(Tab.calls.isEnabled(in: [.status, .communities]))
        XCTAssertFalse(Tab.updates.isEnabled(in: [.calls]))
        XCTAssertFalse(Tab.communities.isEnabled(in: []))
    }

    /// Un lien vers un onglet absent arrive sur Discussions, jamais sur une page vide.
    func test_aLinkToAMissingTab_landsOnChats() {
        XCTAssertEqual(Tab.calls.landing(in: [.status]), .chats)
        XCTAssertEqual(Tab.updates.landing(in: []), .chats)
        XCTAssertEqual(Tab.communities.landing(in: [.communities]), .communities)
    }

    func test_paymentsAreNotATab() {
        for tab in [Tab.updates, .calls, .communities, .chats, .settings] {
            XCTAssertNotEqual(tab.module, .payments)
        }
    }
}
