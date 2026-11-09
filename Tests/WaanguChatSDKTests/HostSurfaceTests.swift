//
//  HostSurfaceTests.swift
//  WaanguChatSDKTests
//
//  What a brand-new app touches: the token store it can create, and the chat view.
//

import XCTest
import SwiftUI
import WaanguCoreKit
@testable import WaanguChatSDK

final class HostSurfaceTests: XCTestCase {

    private func uniqueService() -> String { "com.test.waangu-chat-sdk.\(UUID().uuidString)" }

    func test_theDefaultTokenStore_keepsTheTokensItIsGiven() async throws {
        let store = WaanguChat.makeTokenStore(keychain: MemoryKeychain())
        let soon = Date().addingTimeInterval(3_600)

        try await store.saveTokens(accessToken: "access-1", accessTokenExpiration: soon,
                                   refreshToken: "refresh-1", refreshTokenExpiration: soon.addingTimeInterval(86_400))

        let access = try await store.getAccessToken()
        let refresh = try await store.getRefreshToken()
        XCTAssertEqual(access, "access-1")
        XCTAssertEqual(refresh, "refresh-1")
        let valid = await store.hasValidAccessToken()
        XCTAssertTrue(valid)
    }

    func test_clearingTheTokens_leavesNoSession() async throws {
        let keychain = MemoryKeychain()
        let store = WaanguChat.makeTokenStore(keychain: keychain)
        let soon = Date().addingTimeInterval(3_600)
        try await store.saveTokens(accessToken: "a", accessTokenExpiration: soon,
                                   refreshToken: "r", refreshTokenExpiration: soon)

        try await store.clearTokens()

        let access = try await store.getAccessToken()
        XCTAssertNil(access)
        let valid = await store.hasValidAccessToken()
        XCTAssertFalse(valid)
        let left = await keychain.storedKeys()
        XCTAssertTrue(left.isEmpty, "\(left)")
    }

    /// The host's tokens live under the app's own namespace (`auth.*`). Chat keeps its own session
    /// under `chat.*`; the two must never mix, or the chat session would be sent as the host login.
    func test_theHostTokens_useTheAuthNamespace_notTheChatOne() async throws {
        let keychain = MemoryKeychain()
        let store = WaanguChat.makeTokenStore(keychain: keychain)
        let soon = Date().addingTimeInterval(3_600)

        try await store.saveTokens(accessToken: "a", accessTokenExpiration: soon,
                                   refreshToken: "r", refreshTokenExpiration: soon)

        let keys = await keychain.storedKeys()
        XCTAssertFalse(keys.isEmpty)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("auth.") }, "\(keys)")
    }

    /// The store is exactly what the facade asks for, so a host needs no other type.
    func test_theStoreFitsTheFacade_andTheViewTakesTheFacade() async {
        let service = uniqueService()
        let store = WaanguChat.makeTokenStore(keychainService: service)
        let database = await WaanguChat.makeDatabase()
        let configuration = WaanguChatConfiguration(
            appId: "test", userId: "test-user", chatBaseURL: "https://chat.test.invalid", chatUploadBaseURL: "https://u.test.invalid",
            mainAPIBaseURL: "https://m.test.invalid", realtime: .init(host: "h.test.invalid", port: 8883, useTLS: true),
            keychainService: service)
        let chat = WaanguChat(configuration: configuration, database: database, tokenManager: store)

        if #available(iOS 17.0, *) {
            _ = WaanguChatView(chat: chat)
        }
    }
}
