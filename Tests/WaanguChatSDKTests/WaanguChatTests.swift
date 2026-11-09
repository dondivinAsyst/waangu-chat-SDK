//
//  WaanguChatTests.swift
//  WaanguChatSDKTests
//
//  SDK plan, step 1.9 — the entry point. A "host" here is this test: it knows the facade, its
//  own configuration, its database and its token manager, and nothing else.
//

import XCTest
import WaanguCoreKit
import WaanguAuthKit
import WaanguStorageKit
import WaanguFeatureChat
@testable import WaanguChatSDK

final class WaanguChatTests: XCTestCase {

    private let configuration = WaanguChatConfiguration(
        appId: "test-host", userId: "test-user",
        chatBaseURL: "https://chat.test.invalid",
        chatUploadBaseURL: "https://upload.test.invalid",
        mainAPIBaseURL: "https://main.test.invalid",
        realtime: .init(host: "mqtt.test.invalid", port: 8883, useTLS: true),
        basicAuthToken: nil,
        keychainService: "com.test.waangu-chat-sdk"
    )

    /// The host's own login tokens. Nothing here reaches the Keychain.
    private func hostTokens() -> any TokenManagerProtocol {
        ScriptedHostTokens()
    }

    // MARK: Configuration

    func test_theConfigurationKeepsEveryValueTheHostGave() {
        XCTAssertEqual(configuration.appId, "test-host")
        XCTAssertEqual(configuration.chatBaseURL, "https://chat.test.invalid")
        XCTAssertEqual(configuration.chatUploadBaseURL, "https://upload.test.invalid")
        XCTAssertEqual(configuration.mainAPIBaseURL, "https://main.test.invalid")
        XCTAssertEqual(configuration.realtime.host, "mqtt.test.invalid")
        XCTAssertEqual(configuration.realtime.port, 8883)
        XCTAssertTrue(configuration.realtime.useTLS)
        XCTAssertNil(configuration.basicAuthToken)
        XCTAssertEqual(configuration.keychainService, "com.test.waangu-chat-sdk")
    }

    // MARK: Database

    func test_makeDatabase_holdsChatsTables() async throws {
        let database = await WaanguChat.makeDatabase()
        let item = ChatOutboxItem(actionType: .sendMessage, payload: Data("{}".utf8),
                                  idempotencyKey: "send_message:facade-\(UUID().uuidString)",
                                  conversationId: "c", createdAt: Date(), syncStatus: .pending)

        try await database.save(item)

        let stored = try await database.fetchOne(ChatOutboxItem.self, id: item.id)
        XCTAssertEqual(stored?.idempotencyKey, item.idempotencyKey)
    }

    /// Chat's tables are always there, whatever the host adds: the host list is extra, not instead.
    func test_makeDatabase_keepsChatsTables_whenTheHostAddsItsOwn() async throws {
        let database = await WaanguChat.makeDatabase(hostRegistrations: [ChatDatabaseRegistration.self])
        let item = ChatOutboxItem(actionType: .sendMessage, payload: Data("{}".utf8),
                                  idempotencyKey: "send_message:facade2-\(UUID().uuidString)",
                                  conversationId: "c", createdAt: Date(), syncStatus: .pending)

        try await database.save(item)

        let stored = try await database.fetchOne(ChatOutboxItem.self, id: item.id)
        XCTAssertNotNil(stored)
    }

    // MARK: Wallet stand-ins

    func test_aHostWithoutAWallet_getsUnavailableAnswers_neverInventedOnes() async {
        let usecases = ClosedSharedFeatureUsecases()

        let balance = await usecases.getBalance.execute(forceRefresh: false)
        let recipient = await usecases.checkRecipientPhone.execute(phone: "+25700000000")
        let info = await usecases.userInfo.execute()
        let count = await usecases.countNewNotification.execute()

        for result in [AnyResultError(balance), AnyResultError(recipient), AnyResultError(info), AnyResultError(count)] {
            XCTAssertEqual(result.error, .serviceUnavailable)
        }
    }

    // MARK: What reaches chat

    func test_theHostsValues_reachTheChatDependencies() async throws {
        let sink = CountingSink()
        let database = await WaanguChat.makeDatabase()
        let chat = WaanguChat(configuration: configuration, database: database,
                              tokenManager: hostTokens(), metricsSink: sink)

        let dependencies = try await chat.makeChatDependencies()

        XCTAssertEqual(dependencies.appId, "test-host", "chat logs in as the host's own app")
        XCTAssertEqual(dependencies.userId, "test-user", "chat logs in with the host's user id")
        XCTAssertEqual(dependencies.mainAPIBaseURL, "https://main.test.invalid")
        XCTAssertNotNil(dependencies.callMediaEngine, "calls are on for a host that uses the facade")
        dependencies.metricsSink.record(ChatMetric(name: "probe"))
        XCTAssertEqual(sink.names, ["probe"], "the host's metrics sink is the one chat reports to")
    }

    // MARK: Host with the facade only

    func test_aHostThatOnlyKnowsTheFacade_canPrepareTwice() async {
        let database = await WaanguChat.makeDatabase()
        let chat = WaanguChat(configuration: configuration, database: database, tokenManager: hostTokens())

        await chat.prepare()
        await chat.prepare()
    }

    /// The whole chain: configuration → dependencies → loaded chat → coordinator, with the host
    /// providing only its configuration, database and token manager.
    @MainActor
    func test_aHostThatOnlyKnowsTheFacade_getsAChatCoordinator() async throws {
        let database = await WaanguChat.makeDatabase()
        let chat = WaanguChat(configuration: configuration, database: database, tokenManager: hostTokens())
        await chat.prepare()

        let coordinator = try await chat.makeCoordinator()

        XCTAssertNotNil(coordinator.chatsTabCoordinator)
        await chat.endSession()
    }
}

// MARK: - Doubles

private struct AnyResultError {
    let error: AppError?
    init<T>(_ result: Result<T, AppError>) {
        if case .failure(let error) = result { self.error = error } else { self.error = nil }
    }
}

private actor ScriptedHostTokens: TokenManagerProtocol {
    func saveTokens(accessToken: String, accessTokenExpiration: Date,
                    refreshToken: String, refreshTokenExpiration: Date) async throws {}
    func clearTokens() async throws {}
    func getAccessToken() async throws -> String? { "host-token" }
    func getRefreshToken() async throws -> String? { "host-refresh" }
    func hasValidAccessToken() async -> Bool { true }
    func hasValidRefreshToken() async -> Bool { true }
}

private final class CountingSink: ChatMetricsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _names: [String] = []
    var names: [String] { lock.withLock { _names } }
    func record(_ metric: ChatMetric) { lock.withLock { _names.append(metric.name) } }
}
