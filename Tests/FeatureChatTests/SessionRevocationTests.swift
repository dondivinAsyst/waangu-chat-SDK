//
//  SessionRevocationTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 1.6 — Identity révoque la session (`SESSION_REVOKED`, sur le topic de
//  l'utilisateur) : la session prend fin, les conversations locales restent.
//
//  Règle voulue par Divin : seule une **déconnexion volontaire** efface la base locale. Une
//  session expirée ou révoquée garde les conversations, que l'utilisateur retrouve en se
//  reconnectant avec le même compte.
//
//  Le contenu de l'événement n'est pas documenté (question posée à Chat Core) : seul son type
//  est lu.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class SessionRevocationTests: XCTestCase {

    // MARK: Lecture de l'événement

    private func parse(_ json: String) -> ChatSyncEventDTO? {
        ChatMqttEventParser.parse(data: Data(json.utf8))
    }

    func test_theEventTypeAloneIsEnough() throws {
        let event = try XCTUnwrap(parse(#"{"eventType":"SESSION_REVOKED"}"#))

        XCTAssertTrue(event.isSessionRevocation)
        XCTAssertEqual(event.type, "session_revoked")
    }

    func test_withAnyPayloadShape_itIsStillARevocation() throws {
        let flat = try XCTUnwrap(parse(#"{"eventType":"SESSION_REVOKED","sessionId":"s1","reason":"admin"}"#))
        let nested = try XCTUnwrap(parse(#"{"eventType":"SESSION_REVOKED","payload":{"deviceId":"d1"},"timestamp":"2026-11-06T10:00:00Z"}"#))

        XCTAssertTrue(flat.isSessionRevocation)
        XCTAssertTrue(nested.isSessionRevocation)
    }

    func test_dashesAndCase_areTolerated() throws {
        let event = try XCTUnwrap(parse(#"{"eventType":"session-revoked"}"#))

        XCTAssertTrue(event.isSessionRevocation)
    }

    func test_otherEvents_areNeverARevocation() throws {
        let message = try XCTUnwrap(parse(#"{"eventType":"MESSAGE_SENT","payload":{"codeMessage":"m1","conversationId":"c1","content":{"text":"hi"},"senderId":"u"}}"#))

        XCTAssertFalse(message.isSessionRevocation)
    }

    // MARK: Fin de session

    private actor Journal {
        private(set) var entries: [String] = []
        private(set) var logout: UserDidLogoutEvent?
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

    private func revoke(user: String, journal: Journal,
                        failSession: Bool = false) async -> Bool {
        struct Failed: Error {}
        return await ChatFeature.handleSessionRevoked(
            userId: user,
            eventBus: RecordingEventBus(journal: journal),
            clearSession: { await journal.add("clearSession"); if failSession { throw Failed() } },
            clearChatTokens: { await journal.add("clearChatTokens") })
    }

    func test_aRevocation_endsTheSession_inOrder_asARemoteRevocation() async {
        let journal = Journal()

        let ended = await revoke(user: "usr_42", journal: journal)

        XCTAssertTrue(ended)
        let entries = await journal.entries
        XCTAssertEqual(entries, ["event", "clearSession", "clearChatTokens"],
                       "subscribers see the event before the session is gone; the dead tokens go last")
        let event = await journal.logout
        XCTAssertEqual(event?.userId, "usr_42")
        guard case .remoteRevocation = event?.reason else { return XCTFail("reason: \(String(describing: event?.reason))") }
    }

    func test_whenNoOneIsSignedIn_nothingHappens() async {
        let journal = Journal()

        let ended = await revoke(user: "", journal: journal)

        XCTAssertFalse(ended)
        let entries = await journal.entries
        XCTAssertTrue(entries.isEmpty, "a second event, or one after a logout, has nothing left to end")
    }

    func test_aFailingSessionClear_doesNotKeepTheDeadTokens() async {
        let journal = Journal()

        _ = await revoke(user: "usr_42", journal: journal, failSession: true)

        let entries = await journal.entries
        XCTAssertEqual(entries, ["event", "clearSession", "clearChatTokens"])
    }

    // MARK: Les conversations restent

    func test_aRevocationIsNotADeliberateLogout() {
        XCTAssertFalse(ChatFeature.purgesConversations(onLogout: .remoteRevocation))
        XCTAssertFalse(ChatFeature.purgesConversations(onLogout: .sessionExpired))
        XCTAssertTrue(ChatFeature.purgesConversations(onLogout: .userInitiated), "only a deliberate logout clears")
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "SessionRevocationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private actor Purges {
        private(set) var count = 0
        func record() { count += 1 }
    }

    /// Après une révocation, le même compte qui se reconnecte retrouve ses conversations : le repère
    /// de propriétaire de la base n'a pas bougé, donc rien n'est effacé.
    func test_afterARevocation_theSameUserSigningInAgain_keepsEverything() async {
        let defaults = freshDefaults()
        defaults.set("usr_42|api.prod|t1", forKey: ChatFeature.databaseOwnerKey)
        let journal = Journal()
        let purges = Purges()

        _ = await revoke(user: "usr_42", journal: journal)
        await ChatFeature.handleChatLogin(
            userId: "usr_42", environment: "api.prod", tenant: "t1", defaults: defaults,
            purgeConversations: { await purges.record() },
            restoreFinance: {})

        let count = await purges.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "usr_42|api.prod|t1")
    }

    /// Une **autre** personne qui se connecte après une révocation, elle, ne voit pas les conversations de la précédente.
    func test_afterARevocation_anotherUserSigningIn_stillPurges() async {
        let defaults = freshDefaults()
        defaults.set("usr_42|api.prod|t1", forKey: ChatFeature.databaseOwnerKey)
        let purges = Purges()

        _ = await revoke(user: "usr_42", journal: Journal())
        await ChatFeature.handleChatLogin(
            userId: "usr_77", environment: "api.prod", tenant: "t1", defaults: defaults,
            purgeConversations: { await purges.record() },
            restoreFinance: {})

        let count = await purges.count
        XCTAssertEqual(count, 1)
    }
}
