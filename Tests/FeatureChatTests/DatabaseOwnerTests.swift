//
//  DatabaseOwnerTests.swift
//  FeatureChatTests
//
//  CHAT-FE-SDK-W360-B13, F-12 — un autre compte qui se connecte ne voit pas les
//  conversations laissées par le précédent (invariants 002 et 004).
//

import XCTest
@testable import WaanguFeatureChat

final class DatabaseOwnerTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "DatabaseOwnerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private actor Purges {
        private(set) var count = 0
        func record() { count += 1 }
    }

    func test_decision() {
        typealias D = ChatFeature.DatabaseOwnerDecision
        XCTAssertEqual(ChatFeature.databaseOwnerDecision(stored: nil, loginUserId: "A"), D.adopt)
        XCTAssertEqual(ChatFeature.databaseOwnerDecision(stored: "", loginUserId: "A"), D.adopt)
        XCTAssertEqual(ChatFeature.databaseOwnerDecision(stored: "A", loginUserId: "A"), D.keep)
        XCTAssertEqual(ChatFeature.databaseOwnerDecision(stored: "A", loginUserId: "B"), D.purgeThenAdopt)
        XCTAssertEqual(ChatFeature.databaseOwnerDecision(stored: "A", loginUserId: ""), D.keep, "No identity: touch nothing")
    }

    func test_differentAccount_purgesBeforeAdopting() async {
        let defaults = freshDefaults()
        defaults.set("A", forKey: ChatFeature.databaseOwnerKey)
        let purges = Purges()

        await ChatFeature.reconcileDatabaseOwner(loginUserId: "B", defaults: defaults) {
            // The marker must still name A while the purge runs.
            XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "A")
            await purges.record()
        }

        let count = await purges.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "B")
    }

    // MARK: - Environnement (ADD-3)

    func test_environmentDecision() {
        typealias D = ChatFeature.DatabaseOwnerDecision
        func decide(_ stored: String?, _ env: String) -> D {
            ChatFeature.databaseOwnerDecision(stored: stored, loginUserId: "A", environment: env)
        }
        XCTAssertEqual(decide("A|api.prod", "api.prod"), D.keep)
        XCTAssertEqual(decide("A|api.prod", "api.staging"), D.purgeThenAdopt, "Another server's cache is not shown")
        XCTAssertEqual(decide("A", "api.prod"), D.adopt, "An older marker keeps its data and learns the environment")
        XCTAssertEqual(decide("A|api.prod", ""), D.keep, "Unknown environment: compare nothing")
        XCTAssertEqual(decide("B|api.prod", "api.prod"), D.purgeThenAdopt)
    }

    func test_otherEnvironment_purgesBeforeAdopting() async {
        let defaults = freshDefaults()
        defaults.set("A|api.prod", forKey: ChatFeature.databaseOwnerKey)
        let purges = Purges()

        await ChatFeature.reconcileDatabaseOwner(loginUserId: "A", environment: "api.staging", defaults: defaults) {
            XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "A|api.prod")
            await purges.record()
        }

        let count = await purges.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "A|api.staging")
    }

    func test_olderMarker_isRewrittenWithoutPurging() async {
        let defaults = freshDefaults()
        defaults.set("A", forKey: ChatFeature.databaseOwnerKey)
        let purges = Purges()

        await ChatFeature.reconcileDatabaseOwner(loginUserId: "A", environment: "api.prod", defaults: defaults) { await purges.record() }

        let count = await purges.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "A|api.prod")
    }

    func test_sameAccount_keepsEverything() async {
        let defaults = freshDefaults()
        defaults.set("A", forKey: ChatFeature.databaseOwnerKey)
        let purges = Purges()

        await ChatFeature.reconcileDatabaseOwner(loginUserId: "A", defaults: defaults) { await purges.record() }

        let count = await purges.count
        XCTAssertEqual(count, 0)
    }

    func test_installWithoutMarker_adoptsWithoutPurging() async {
        let defaults = freshDefaults()
        let purges = Purges()

        await ChatFeature.reconcileDatabaseOwner(loginUserId: "A", defaults: defaults) { await purges.record() }

        let count = await purges.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "A")
    }
}
