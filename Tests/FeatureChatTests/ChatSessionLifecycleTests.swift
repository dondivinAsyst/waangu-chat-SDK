//
//  ChatSessionLifecycleTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 1.8 — ce que le Chat fait quand la session de l'hôte change.
//  Ces règles vivaient dans le `SessionManager` de l'application, sans test.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class ChatSessionLifecycleTests: XCTestCase {

    // MARK: Fabrique

    private struct Rig {
        let lifecycle: ChatSessionLifecycle
        let realtime: RecordingRealtimeClient
        let sync: EventSync
        let logger: RecordingLogger
        let events: EventLog
    }

    private func makeRig(access: Bool = true,
                         refresh: Bool = true,
                         callActive: Bool = false,
                         connectError: Error? = nil,
                         renew: (@Sendable () async -> Bool)? = nil) -> Rig {
        let events = EventLog()
        let realtime = RecordingRealtimeClient()
        realtime.connectError = connectError
        realtime.onEvent = { name in events.add(name) }
        let sync = EventSync(events: events)
        let logger = RecordingLogger()
        let lifecycle = ChatSessionLifecycle(
            realtime: realtime,
            sync: ChatSyncRunner(sync: sync),
            chatTokenManager: FlagTokens(access: access, refresh: refresh),
            logger: logger,
            retainsRealtimeInBackground: { callActive },
            renewSession: renew
        )
        return Rig(lifecycle: lifecycle, realtime: realtime, sync: sync, logger: logger, events: events)
    }

    /// La synchro est lancée sans être attendue : on attend qu'elle ait écrit.
    private func waitFor(_ rig: Rig, _ name: String) async throws {
        for _ in 0..<200 {
            if rig.events.names.contains(name) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("\(name) jamais vu : \(rig.events.names)")
    }

    // MARK: Connexion et retour au premier plan

    func test_signIn_connectsRealtime_thenSyncs() async throws {
        let rig = makeRig()

        await rig.lifecycle.userDidSignIn()
        try await waitFor(rig, "pull")

        XCTAssertEqual(rig.realtime.connectCount, 1)
        let names = rig.events.names
        XCTAssertEqual(names, ["connect", "flush", "pull"], "la connexion précède la synchro")
    }

    func test_foreground_doesTheSameAsSignIn() async throws {
        let rig = makeRig()

        await rig.lifecycle.appDidEnterForeground()
        try await waitFor(rig, "pull")

        XCTAssertEqual(rig.realtime.connectCount, 1)
        let names = rig.events.names
        XCTAssertEqual(names, ["connect", "flush", "pull"])
    }

    /// Comportement du code remplacé : sans jeton on ne se connecte pas, mais la synchro est
    /// quand même demandée. Fixé ici pour qu'un changement se voie.
    func test_withoutAnyToken_realtimeStaysOff_butSyncStillRuns() async throws {
        let rig = makeRig(access: false, refresh: false)

        await rig.lifecycle.userDidSignIn()
        try await waitFor(rig, "pull")

        XCTAssertEqual(rig.realtime.connectCount, 0)
        let names = rig.events.names
        XCTAssertEqual(names, ["flush", "pull"])
    }

    /// Un jeton d'accès expiré mais un jeton de rafraîchissement valable : la connexion
    /// repart, c'est le transport qui renouvellera.
    func test_aValidRefreshTokenAlone_isEnoughToConnect() async throws {
        let rig = makeRig(access: false, refresh: true)

        await rig.lifecycle.userDidSignIn()
        try await waitFor(rig, "pull")

        XCTAssertEqual(rig.realtime.connectCount, 1)
    }

    // MARK: Session de chat expirée

    /// La session de chat de 24 h a pris fin pendant que l'application restait ouverte : si l'hôte
    /// sait se reconnecter, le temps réel repart.
    func test_anExpiredSession_isRenewed_thenRealtimeConnects() async throws {
        let events = EventLog()
        let rig = makeRig(access: false, refresh: false, renew: { events.add("renew"); return true })

        await rig.lifecycle.appDidEnterForeground()
        try await waitFor(rig, "pull")

        XCTAssertEqual(events.names, ["renew"])
        XCTAssertEqual(rig.realtime.connectCount, 1)
    }

    func test_anExpiredSession_staysOffline_whenTheNewLoginFails() async throws {
        let rig = makeRig(access: false, refresh: false, renew: { false })

        await rig.lifecycle.appDidEnterForeground()
        try await waitFor(rig, "pull")

        XCTAssertEqual(rig.realtime.connectCount, 0)
    }

    func test_aValidSession_isNotRenewed() async throws {
        let events = EventLog()
        let rig = makeRig(access: true, refresh: true, renew: { events.add("renew"); return true })

        await rig.lifecycle.appDidEnterForeground()
        try await waitFor(rig, "pull")

        XCTAssertEqual(events.names, [])
        XCTAssertEqual(rig.realtime.connectCount, 1)
    }

    func test_aFailedConnect_isLogged_notThrown_andSyncStillRuns() async throws {
        struct Boom: Error {}
        let rig = makeRig(connectError: Boom())

        await rig.lifecycle.userDidSignIn()
        try await waitFor(rig, "pull")

        let warnings = await rig.logger.messages(at: .warning)
        XCTAssertEqual(warnings.count, 1, "\(warnings)")
        XCTAssertTrue(warnings[0].hasPrefix("Realtime connect failed"), warnings[0])
    }

    // MARK: Arrière-plan

    func test_background_disconnectsRealtime_asSuspended() async {
        let rig = makeRig()

        await rig.lifecycle.appDidEnterBackground()

        XCTAssertEqual(rig.realtime.disconnects, [.backgroundSuspended])
    }

    /// CallKit peut répondre depuis l'écran verrouillé : sans MQTT, `call-join` ne part pas.
    func test_background_keepsRealtime_whileACallIsActive() async {
        let rig = makeRig(callActive: true)

        await rig.lifecycle.appDidEnterBackground()

        XCTAssertEqual(rig.realtime.disconnects, [])
        let infos = await rig.logger.messages(at: .info)
        XCTAssertEqual(infos, ["Keeping realtime in background — call in progress"])
    }

    // MARK: Déconnexion

    func test_signOut_stopsSync_thenDisconnects_asUserInitiated() async {
        let rig = makeRig()

        await rig.lifecycle.userDidSignOut()

        XCTAssertEqual(rig.realtime.disconnects, [.userInitiated])
        let names = rig.events.names
        XCTAssertEqual(names, ["stop", "disconnect"], "la synchro s'arrête avant la coupure")
    }
}

// MARK: - Doublures

/// Journal synchrone : l'ordre des entrées est celui des appels.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _names: [String] = []

    var names: [String] { lock.withLock { _names } }
    func add(_ name: String) { lock.withLock { _names.append(name) } }
}

/// Synchro qui consigne ses appels dans le journal commun.
private struct EventSync: FeatureSyncProtocol {
    let featureName = "events"
    let syncPriority: SyncPriority = .high
    let events: EventLog

    func flushOutbox() async { events.add("flush") }
    func pullMissedEvents() async { events.add("pull") }
    func stopSync() async { events.add("stop") }
}

private actor FlagTokens: ChatTokenManagerProtocol {
    private let access: Bool
    private let refresh: Bool
    init(access: Bool, refresh: Bool) { self.access = access; self.refresh = refresh }

    func saveTokens(accessToken: String, accessTokenExpiration: Date,
                    refreshToken: String, refreshTokenExpiration: Date) async throws {}
    func clearTokens() async throws {}
    func getAccessToken() async throws -> String? { access ? "a" : nil }
    func getRefreshToken() async throws -> String? { refresh ? "r" : nil }
    func hasValidAccessToken() async -> Bool { access }
    func hasValidRefreshToken() async -> Bool { refresh }
}

private actor RecordingLogger: AppLoggerProtocol {
    private var entries: [(level: LogLevel, message: String)] = []

    func messages(at level: LogLevel) -> [String] {
        entries.filter { $0.level == level }.map(\.message)
    }

    func log(_ message: String, level: LogLevel, file: String, function: String, line: Int) async {
        entries.append((level, message))
    }
    func addObserver(_ observer: any LogObserverProtocol) async {}
    func removeAllObservers() async {}
    var minLevel: LogLevel { get async { .debug } }
}
