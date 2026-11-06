//
//  SessionSequenceTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 1.14 — les trois chemins de `ChatFeature` qu'aucun test ne
//  pouvait atteindre : fin de session, ouverture de session, reprise après un
//  événement live refusé.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Ordre des appels, partagé entre tâches.
private actor CallLog {
    private(set) var calls: [String] = []
    func record(_ call: String) { calls.append(call) }
}

final class SessionSequenceTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "SessionSequenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    // MARK: Fin de session

    func test_userLogout_resetsFinanceForTheEventsUser_thenPurgesConversations() async {
        let log = CallLog()

        await ChatFeature.handleLogout(
            UserDidLogoutEvent(userId: "user-A", reason: .userInitiated),
            resetFinancialState: { await log.record("finance:\($0)") },
            purgeConversations: { await log.record("purge") }
        )

        let calls = await log.calls
        XCTAssertEqual(calls, ["finance:user-A", "purge"])
    }

    /// Une session qui expire, est suspendue ou révoquée garde les conversations.
    func test_endedSessionsNotChosenByTheUser_keepConversations() async {
        for reason: UserDidLogoutEvent.Reason in [.sessionExpired, .accountSuspended, .remoteRevocation] {
            let log = CallLog()

            await ChatFeature.handleLogout(
                UserDidLogoutEvent(userId: "user-A", reason: reason),
                resetFinancialState: { await log.record("finance:\($0)") },
                purgeConversations: { await log.record("purge") }
            )

            let calls = await log.calls
            XCTAssertEqual(calls, ["finance:user-A"], "\(reason)")
        }
    }

    // MARK: Ouverture de session

    /// Un autre compte : la base est purgée **avant** que la finance soit relue.
    func test_otherAccountLogin_purgesBeforeRestoringFinance() async {
        let defaults = freshDefaults()
        await ChatFeature.reconcileDatabaseOwner(loginUserId: "user-A", environment: "api.test", defaults: defaults) {}
        let log = CallLog()

        await ChatFeature.handleChatLogin(
            userId: "user-B", environment: "api.test", defaults: defaults,
            purgeConversations: { await log.record("purge") },
            restoreFinance: { await log.record("finance") }
        )

        let calls = await log.calls
        XCTAssertEqual(calls, ["purge", "finance"])
    }

    func test_sameAccountLogin_restoresFinanceWithoutPurging() async {
        let defaults = freshDefaults()
        await ChatFeature.reconcileDatabaseOwner(loginUserId: "user-A", environment: "api.test", defaults: defaults) {}
        let log = CallLog()

        await ChatFeature.handleChatLogin(
            userId: "user-A", environment: "api.test", defaults: defaults,
            purgeConversations: { await log.record("purge") },
            restoreFinance: { await log.record("finance") }
        )

        let calls = await log.calls
        XCTAssertEqual(calls, ["finance"])
    }

    // MARK: Reprise après un événement live refusé

    func test_refusalsWhileASyncIsPending_runOneSync() async {
        let log = CallLog()
        let recovery = LiveEventRecovery(delayNanoseconds: 50_000_000) { await log.record("sync") }

        let first = await recovery.schedule()
        let second = await recovery.schedule()
        let third = await recovery.schedule()
        await recovery.waitUntilIdle()

        XCTAssertEqual([first, second, third], [true, false, false])
        let calls = await log.calls
        XCTAssertEqual(calls, ["sync"])
    }

    /// Des refus simultanés venus de tâches différentes : toujours une seule synchro.
    func test_concurrentRefusals_runOneSync() async {
        let log = CallLog()
        let recovery = LiveEventRecovery(delayNanoseconds: 50_000_000) { await log.record("sync") }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { await recovery.schedule() } }
        }
        await recovery.waitUntilIdle()

        let calls = await log.calls
        XCTAssertEqual(calls, ["sync"])
    }

    /// Une fois la synchro faite, un nouveau refus en relance une.
    func test_aRefusalAfterTheSync_schedulesAnother() async {
        let log = CallLog()
        let recovery = LiveEventRecovery(delayNanoseconds: 0) { await log.record("sync") }

        await recovery.schedule()
        await recovery.waitUntilIdle()
        let again = await recovery.schedule()
        await recovery.waitUntilIdle()

        XCTAssertTrue(again)
        let calls = await log.calls
        XCTAssertEqual(calls, ["sync", "sync"])
    }
}
