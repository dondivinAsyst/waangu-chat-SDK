//
//  ChatLoginIdentityTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 1.3 — qui est l'utilisateur d'une session de chat.
//
//  Réponse d'Identity (2026-11-05) : l'utilisateur est l'`appUserId` que le webhook
//  `verify-user` de l'application renvoie pour le jeton Bearer. `user_identifier`,
//  dans le corps, est facultatif et ne sert que de nom de secours. Le Chat n'envoie donc
//  plus d'identifiant venu du portefeuille, et `AuthRepository` n'a plus de portefeuille.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class ChatLoginIdentityTests: XCTestCase {

    // MARK: Le corps de la requête

    private func makeRequest(userIdentifier: String? = nil) -> AuthRequest {
        let device = DeviceContext(deviceId: "device-1", deviceModel: "iPhone", brandName: "Apple",
                                   manufacturer: "Apple", osVersion: "18.0", appVersion: "1.0",
                                   buildNumber: "1", platformOS: "iOS")
        return AuthRequest.mapper(deviceInfo: device, userIdentifier: userIdentifier)
    }

    func test_byDefault_noUserIdentifierIsSent() throws {
        let body = try makeRequest().toDictionary()

        // Only the device: no identifier under any name, not just `user_identifier`.
        XCTAssertEqual(Set(body.keys), ["device"], "\(body)")
    }

    /// Une valeur donnée reste envoyée : le champ est facultatif, pas supprimé.
    func test_aGivenIdentifier_isStillSentUnderItsName() throws {
        let body = try makeRequest(userIdentifier: "fallback-name").toDictionary()

        XCTAssertEqual(body["user_identifier"] as? String, "fallback-name")
    }

    func test_theDeviceIsStillDescribed() throws {
        let body = try makeRequest().toDictionary()
        let device = try XCTUnwrap(body["device"] as? [String: Any])

        XCTAssertEqual(device["deviceId"] as? String, "device-1")
        XCTAssertEqual(device["platform"] as? String, "iOS")
    }

    // MARK: Le dépôt d'authentification

    func test_authenticate_sendsNoIdentifier_andNeedsNoWallet() async throws {
        let http = ScriptedAuthDataSource(result: .success(Self.reply(userId: "app-user-1")))
        let repository = AuthRepository(deviceInfoProvider: FixedDeviceInfo(),
                                        httpDataSource: http,
                                        chatTokenManager: RecordingChatTokens())

        let session = await repository.authenticate()

        XCTAssertNotNil(session)
        XCTAssertEqual(http.requests.count, 1)
        let body = try XCTUnwrap(http.requests.first).toDictionary()
        XCTAssertEqual(Set(body.keys), ["device"], "\(body)")
    }

    /// L'identité de la session est celle que le serveur renvoie, jamais celle du téléphone.
    func test_theSessionUser_isTheOneTheServerReturns() async {
        let http = ScriptedAuthDataSource(result: .success(Self.reply(userId: "server-user-9")))
        let repository = AuthRepository(deviceInfoProvider: FixedDeviceInfo(),
                                        httpDataSource: http,
                                        chatTokenManager: RecordingChatTokens())

        let session = await repository.authenticate()

        XCTAssertEqual(session?.userId, "server-user-9")
        XCTAssertEqual(session?.tenantId, "tenant-1")
        XCTAssertEqual(session?.country, "BI")
    }

    func test_theSessionId_isStoredAsTheChatToken() async throws {
        let tokens = RecordingChatTokens()
        let http = ScriptedAuthDataSource(result: .success(Self.reply(userId: "u", sessionId: "session-abc")))
        let repository = AuthRepository(deviceInfoProvider: FixedDeviceInfo(),
                                        httpDataSource: http, chatTokenManager: tokens)

        _ = await repository.authenticate()

        let saved = await tokens.saved
        XCTAssertEqual(saved.map(\.access), ["session-abc"])
    }

    func test_aRefusedLogin_returnsNoSession_andStoresNothing() async {
        let tokens = RecordingChatTokens()
        let http = ScriptedAuthDataSource(result: .success(Self.reply(userId: "u", status: 401)))
        let repository = AuthRepository(deviceInfoProvider: FixedDeviceInfo(),
                                        httpDataSource: http, chatTokenManager: tokens)

        let session = await repository.authenticate()

        XCTAssertNil(session)
        let saved = await tokens.saved
        XCTAssertTrue(saved.isEmpty)
    }

    func test_aFailedCall_returnsNoSession() async {
        let http = ScriptedAuthDataSource(result: .failure(URLError(.notConnectedToInternet)))
        let repository = AuthRepository(deviceInfoProvider: FixedDeviceInfo(),
                                        httpDataSource: http, chatTokenManager: RecordingChatTokens())

        let session = await repository.authenticate()

        XCTAssertNil(session)
    }

    // MARK: Doublures

    private static func reply(userId: String, sessionId: String = "session-1", status: Int = 200) -> APIAuthResponse {
        APIAuthResponse(
            message: status == 200 ? "ok" : "refused",
            status: status,
            data: AuthSessionData(
                redirectUrl: "", sessionId: sessionId, appId: "app-1", userId: userId,
                email: "", name: "", tenantId: "tenant-1", organisationId: "org-1",
                country: "BI", phone: "", expiresAt: "2030-01-01T00:00:00Z"))
    }
}

private final class ScriptedAuthDataSource: HTTPAuthDataSourceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<APIAuthResponse, Error>
    private var _requests: [AuthRequest] = []

    init(result: Result<APIAuthResponse, Error>) { self.result = result }

    var requests: [AuthRequest] { lock.withLock { _requests } }

    func authenticate(_ request: AuthRequest) async throws -> APIAuthResponse {
        lock.withLock { _requests.append(request) }
        return try result.get()
    }
}

private struct FixedDeviceInfo: DeviceInfoProvidingProtocol {
    func captureSnapshot() -> DeviceInfoSnapshot {
        DeviceInfoSnapshot(processorCount: 6, physicalMemoryMB: 4_096, modelIdentifier: "iPhone", systemVersion: "18.0")
    }

    func captureDeviceContext() -> DeviceContext {
        DeviceContext(deviceId: "device-1", deviceModel: "iPhone", brandName: "Apple",
                      manufacturer: "Apple", osVersion: "18.0", appVersion: "1.0",
                      buildNumber: "1", platformOS: "iOS")
    }
}

private actor RecordingChatTokens: ChatTokenManagerProtocol {
    struct Saved: Equatable { let access: String; let refresh: String }
    private(set) var saved: [Saved] = []

    func saveTokens(accessToken: String, accessTokenExpiration: Date,
                    refreshToken: String, refreshTokenExpiration: Date) async throws {
        saved.append(Saved(access: accessToken, refresh: refreshToken))
    }
    func clearTokens() async throws { saved.removeAll() }
    func getAccessToken() async throws -> String? { saved.last?.access }
    func getRefreshToken() async throws -> String? { saved.last?.refresh }
    func hasValidAccessToken() async -> Bool { !saved.isEmpty }
    func hasValidRefreshToken() async -> Bool { !saved.isEmpty }
}
