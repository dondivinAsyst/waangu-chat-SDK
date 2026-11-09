//
//  OverridesTests.swift
//  WaanguChatSDKTests
//
//  SDK plan, step 1.9 (parity) — what a host can still substitute, and the sign-out split the
//  Waangu app relies on.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
import WaanguFeatureChat
@testable import WaanguChatSDK

final class ChatDependencyOverridesTests: XCTestCase {

    private func configuration(payments: Bool) -> WaanguChatConfiguration {
        WaanguChatConfiguration(
            appId: "test-host", userId: "test-user",
            chatBaseURL: "https://chat.test.invalid",
            chatUploadBaseURL: "https://upload.test.invalid",
            mainAPIBaseURL: "https://main.test.invalid",
            realtime: .init(host: "mqtt.test.invalid", port: 8883, useTLS: true),
            keychainService: "com.test.waangu-chat-sdk",
            modules: payments ? ChatModule.standard.union([.payments]) : ChatModule.standard
        )
    }

    private func dependencies(payments: Bool,
                              overrides: @escaping () async throws -> ChatDependencyOverrides) async throws -> ChatDependencies {
        let database = await WaanguChat.makeDatabase()
        let chat = WaanguChat(configuration: configuration(payments: payments), database: database,
                              tokenManager: HostTokens(), overrides: overrides)
        return try await chat.makeChatDependencies()
    }

    /// A host with no overrides gets exactly the facade's own choices.
    func test_noOverrides_leavesTheFacadesChoices() async throws {
        let deps = try await dependencies(payments: false) { ChatDependencyOverrides() }

        XCTAssertTrue(deps.sharedFeatureUsecases is ClosedSharedFeatureUsecases)
        XCTAssertTrue(deps.auditEmitter is UnavailableAuditEmitter)
        XCTAssertTrue(deps.tokenRotation is UnavailableTokenRotation)
        XCTAssertTrue(deps.attestationVerifier is UnavailableAttestationVerifier)
    }

    /// A value given by the host wins over the live Chat Core service.
    func test_anOverride_winsOverTheLiveService() async throws {
        let deps = try await dependencies(payments: true) {
            var overrides = ChatDependencyOverrides()
            overrides.recipientResolver = ClosedRecipientResolver()
            return overrides
        }

        XCTAssertTrue(deps.recipientResolver is ClosedRecipientResolver)
        XCTAssertFalse(deps.killSwitch is ClosedKillSwitch, "services not overridden stay live")
    }

    /// The simulated backend of the Waangu app: payments off, services supplied one by one.
    func test_aServiceGivenWithPaymentsOff_isUsed() async throws {
        let deps = try await dependencies(payments: false) {
            var overrides = ChatDependencyOverrides()
            overrides.financialObjectPersistence = RecordingPersistence()
            return overrides
        }

        XCTAssertTrue(deps.financialObjectPersistence is RecordingPersistence)
        XCTAssertTrue(deps.killSwitch is ClosedKillSwitch)
    }

    func test_theHostsWalletUseCases_reachChat() async throws {
        let deps = try await dependencies(payments: false) {
            var overrides = ChatDependencyOverrides()
            overrides.sharedFeatureUsecases = HostWallet()
            return overrides
        }

        XCTAssertTrue(deps.sharedFeatureUsecases is HostWallet)
    }

    func test_theOverridesAreAskedForWhenChatIsBuilt_notBefore() async throws {
        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        let database = await WaanguChat.makeDatabase()
        let chat = WaanguChat(configuration: configuration(payments: false), database: database,
                              tokenManager: HostTokens(),
                              overrides: { counter.n += 1; return ChatDependencyOverrides() })

        await chat.prepare()
        XCTAssertEqual(counter.n, 0)

        _ = try await chat.makeChatDependencies()
        XCTAssertEqual(counter.n, 1)
    }

    func test_aFailingOverrideProvider_failsTheBuild_withItsError() async {
        struct Boom: Error, Equatable {}
        do {
            _ = try await dependencies(payments: false) { throw Boom() }
            XCTFail("must throw")
        } catch {
            XCTAssertEqual(error as? Boom, Boom())
        }
    }

    // MARK: Modules

    private func dependencies(modules: Set<ChatModule>) async throws -> ChatDependencies {
        let database = await WaanguChat.makeDatabase()
        let config = WaanguChatConfiguration(
            appId: "test-host", userId: "test-user", chatBaseURL: "https://chat.test.invalid",
            chatUploadBaseURL: "https://upload.test.invalid", mainAPIBaseURL: "https://main.test.invalid",
            realtime: .init(host: "mqtt.test.invalid", port: 8883, useTLS: true),
            keychainService: "com.test.waangu-chat-sdk", modules: modules)
        let chat = WaanguChat(configuration: config, database: database, tokenManager: HostTokens())
        return try await chat.makeChatDependencies()
    }

    func test_theDefaultModules_areEverythingButPayments() {
        let config = WaanguChatConfiguration(
            appId: "a", userId: "test-user", chatBaseURL: "c", chatUploadBaseURL: "u", mainAPIBaseURL: "m",
            realtime: .init(host: "h", port: 1, useTLS: false), keychainService: "k")

        XCTAssertEqual(config.modules, ChatModule.standard)
    }

    func test_theHostsModules_reachChat() async throws {
        let deps = try await dependencies(modules: [.calls])

        XCTAssertEqual(deps.enabledModules, [.calls])
    }

    func test_withoutCalls_thereIsNoCallEngine() async throws {
        let on = try await dependencies(modules: [.calls])
        let off = try await dependencies(modules: [.status])

        XCTAssertNotNil(on.callMediaEngine)
        XCTAssertNil(off.callMediaEngine, "no engine means nothing can start or answer a call")
    }

    func test_paymentsFollowTheirModule() async throws {
        let on = try await dependencies(modules: [.payments])
        let off = try await dependencies(modules: ChatModule.standard)

        XCTAssertFalse(on.killSwitch is ClosedKillSwitch)
        XCTAssertTrue(off.killSwitch is ClosedKillSwitch)
    }

    // MARK: Parts a host may still need

    func test_thePartsAHostMayNeed_areTheOnesChatUses() async throws {
        let database = await WaanguChat.makeDatabase()
        let chat = WaanguChat(configuration: configuration(payments: false), database: database,
                              tokenManager: HostTokens())

        let deps = try await chat.makeChatDependencies()

        XCTAssertTrue(chat.realtime as AnyObject === deps.realtime as AnyObject,
                      "a host that disconnects realtime must reach the same client")
        XCTAssertTrue(chat.chatTokens as AnyObject === deps.chatTokenManager as AnyObject)
    }

    // MARK: Sign-out

    @MainActor
    func test_userDidSignOut_keepsChatLoaded_endSessionUnloadsIt() async throws {
        let database = await WaanguChat.makeDatabase()
        let chat = WaanguChat(configuration: configuration(payments: false), database: database,
                              tokenManager: HostTokens())
        await chat.prepare()
        _ = try await chat.makeCoordinator()
        let loaded = try await FeatureRegistry.shared.feature(ChatFeature.self)

        await chat.userDidSignOut()
        let afterSignOut = try await FeatureRegistry.shared.feature(ChatFeature.self)
        XCTAssertTrue(loaded === afterSignOut, "the host drops its coordinator before chat is unloaded")

        await chat.endSession()
        let afterEnd = try await FeatureRegistry.shared.feature(ChatFeature.self)
        XCTAssertFalse(loaded === afterEnd, "the next account must not inherit the previous chat")
        await chat.endSession()
    }
}

// MARK: - Doubles

private struct HostWallet: SharedFeatureUsecasesProtocol {
    private let inner = ClosedSharedFeatureUsecases()
    var getBalance: any GetBalanceUseCaseProtocol { inner.getBalance }
    var checkRecipientPhone: any CheckRecipientPhoneUseCaseProtocol { inner.checkRecipientPhone }
    var userInfo: any UserInfoUseCaseProtocol { inner.userInfo }
    var countNewNotification: any CountNewNotificationUseCaseProtocol { inner.countNewNotification }
}

private actor RecordingPersistence: FinancialObjectPersisting {
    func load() async -> [PersistedFinancialObject] { [] }
    func save(_ object: PersistedFinancialObject) async {}
    func remove(type: String, id: String) async {}
    func clear() async {}
}
