//
//  PlugAndPlayTests.swift
//  WaanguChatSDKTests
//
//  The short form a new app uses: an app id and an environment, then its own access token.
//

import XCTest
import WaanguCoreKit
import WaanguFeatureChat
@testable import WaanguChatSDK

final class PlugAndPlayTests: XCTestCase {

    private func configuration(keychainService: String? = nil,
                               modules: Set<ChatModule> = ChatModule.standard) -> WaanguChatConfiguration {
        WaanguChatConfiguration(
            appId: "app", userId: "test-user",
            chatBaseURL: "https://chat.test.invalid",
            chatUploadBaseURL: "https://upload.test.invalid",
            mainAPIBaseURL: "https://api.test.invalid",
            realtime: .init(host: "mqtt.test.invalid", port: 8883, useTLS: true),
            keychainService: keychainService,
            modules: modules)
    }

    /// The SDK holds no server address: what the host passes is what chat uses.
    func test_theServersAreExactlyTheOnesTheHostGave() {
        let configuration = configuration()

        XCTAssertEqual(configuration.appId, "app")
        XCTAssertEqual(configuration.chatBaseURL, "https://chat.test.invalid")
        XCTAssertEqual(configuration.chatUploadBaseURL, "https://upload.test.invalid")
        XCTAssertEqual(configuration.mainAPIBaseURL, "https://api.test.invalid")
        XCTAssertEqual(configuration.realtime.host, "mqtt.test.invalid")
        XCTAssertEqual(configuration.realtime.port, 8883)
        XCTAssertTrue(configuration.realtime.useTLS)
    }

    func test_theKeychainServiceDefaultsToTheBundle_andCanBeSet() {
        XCTAssertFalse(configuration().keychainService.isEmpty)
        XCTAssertEqual(configuration(keychainService: "svc").keychainService, "svc")
    }

    func test_paymentsStayOff_unlessAsked() {
        XCTAssertFalse(configuration().modules.contains(.payments))
        XCTAssertTrue(configuration(modules: ChatModule.standard.union([.payments])).modules.contains(.payments))
    }

    // MARK: Host token

    func test_theProvidedToken_isReadFromTheHostEachTime() async throws {
        let box = TokenBox("t1")
        let tokens = ProvidedTokenManager(provider: { await box.value })

        let first = try await tokens.getAccessToken()
        await box.set("t2")
        let second = try await tokens.getAccessToken()

        XCTAssertEqual(first, "t1")
        XCTAssertEqual(second, "t2", "a renewed host token is used without telling chat")
    }

    func test_withoutAHostToken_thereIsNoSession() async throws {
        let tokens = ProvidedTokenManager(provider: { nil })

        let access = try await tokens.getAccessToken()
        XCTAssertNil(access)
        let valid = await tokens.hasValidAccessToken()
        XCTAssertFalse(valid)
    }

    func test_chatNeverStoresTheHostTokens() async throws {
        let tokens = ProvidedTokenManager(provider: { "host" })
        try await tokens.saveTokens(accessToken: "x", accessTokenExpiration: .distantFuture,
                                    refreshToken: "y", refreshTokenExpiration: .distantFuture)

        let access = try await tokens.getAccessToken()
        XCTAssertEqual(access, "host")
        let refresh = try await tokens.getRefreshToken()
        XCTAssertNil(refresh)
    }
}

private actor TokenBox {
    var value: String?
    init(_ value: String?) { self.value = value }
    func set(_ new: String?) { value = new }
}

// MARK: - Sign-out

final class SignOutTests: XCTestCase {

    /// Only the user's own sign-out may clear the device's conversations.
    func test_signOut_announcesAUserInitiatedLogout() async throws {
        let seen = ReasonBox()
        let task = Task {
            for await event in EventBus.shared.subscribe(to: UserDidLogoutEvent.self) {
                await seen.add(event.reason)
            }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let chat = WaanguChat(configuration: WaanguChatConfiguration(
                                  appId: "a", userId: "test-user", chatBaseURL: "https://c.test.invalid", chatUploadBaseURL: "https://u.test.invalid",
                                  mainAPIBaseURL: "https://m.test.invalid", realtime: .init(host: "h.test.invalid", port: 8883, useTLS: true)),
                              database: await WaanguChat.makeDatabase(),
                              tokenManager: ProvidedTokenManager(provider: { nil }))

        await chat.signOut()
        for _ in 0..<100 where await seen.reasons.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        task.cancel()

        let reasons = await seen.reasons
        XCTAssertEqual(reasons.count, 1)
        XCTAssertTrue(reasons.allSatisfy { $0 == .userInitiated }, "\(reasons)")
    }
}

private actor ReasonBox {
    var reasons: [UserDidLogoutEvent.Reason] = []
    func add(_ reason: UserDidLogoutEvent.Reason) { reasons.append(reason) }
}
