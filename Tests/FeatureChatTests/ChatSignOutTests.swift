//
//  ChatSignOutTests.swift
//  FeatureChatTests
//
//  Harness Bloc 2 §16, M1 — « Se déconnecter » émet `UserDidLogoutEvent`
//  avant d'effacer la session.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class ChatSignOutTests: XCTestCase {

    private actor Journal {
        var entries: [String] = []
        var logout: UserDidLogoutEvent?
        func add(_ entry: String) { entries.append(entry) }
        func record(_ event: UserDidLogoutEvent) { logout = event; entries.append("event") }
    }

    private final class RecordingEventBus: EventBusProtocol, @unchecked Sendable {
        let journal: Journal
        init(journal: Journal) { self.journal = journal }
        func publish<E: DomainEvent>(_ event: E) async {
            if let logout = event as? UserDidLogoutEvent { await journal.record(logout) }
        }
        func subscribe<E: DomainEvent>(to type: E.Type) -> AsyncStream<E> { AsyncStream { $0.finish() } }
        func stream<E: DomainEvent>(for type: E.Type) -> AsyncStream<E> { AsyncStream { $0.finish() } }
        func on<E: MatchableDomainEvent>(_ target: E) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    }

    func test_signOut_publishesTheLogoutEvent_thenClearsTheSession() async {
        let journal = Journal()
        await ChatFeature.signOut(userId: "usr_42",
                                  eventBus: RecordingEventBus(journal: journal),
                                  clearSession: { await journal.add("clearSession") })

        let entries = await journal.entries
        let event = await journal.logout
        XCTAssertEqual(entries, ["event", "clearSession"], "Subscribers must see the event before the session is gone")
        XCTAssertEqual(event?.userId, "usr_42")
        guard case .userInitiated = event?.reason else { return XCTFail("reason: \(String(describing: event?.reason))") }
    }

    /// A failing session clear must not stop the event: the purges still run.
    func test_signOut_stillPublishes_whenClearingTheSessionFails() async {
        struct ClearFailed: Error {}
        let journal = Journal()
        await ChatFeature.signOut(userId: "usr_42",
                                  eventBus: RecordingEventBus(journal: journal),
                                  clearSession: { throw ClearFailed() })
        let event = await journal.logout
        XCTAssertNotNil(event)
    }
}
