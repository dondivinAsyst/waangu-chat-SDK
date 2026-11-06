//
//  SessionRenewalTests.swift
//  NetworkKitTests
//
//  Plan SDK, étape 1.7 — expiration et renouvellement de session.
//
//  Ce que ces tests établissent, sans rien supposer du serveur :
//  - `TokenManager` (AuthKit) : stockage, validité, nettoyage, isolation des
//    espaces de clés ;
//  - `JWTValidator` (AuthKit) : lecture de `exp` uniquement ;
//  - `APIClient` (NetworkKit) face à un 401.
//
//  Constat consigné par le dernier groupe : **aucun renouvellement de jeton
//  n'existe**. Sur un 401, `APIClient` passe l'erreur aux middlewares, aucun ne
//  la traite, puis rejoue la requête une fois avec le même jeton et échoue. Le
//  contrat de renouvellement (route, rotation, réutilisation) appartient à IAM
//  (Trésor) ; ces tests figent le comportement actuel pour que l'arrivée de ce
//  contrat se voie.
//

import XCTest
import WaanguCoreKit
import WaanguAuthKit
@testable import WaanguNetworkKit

// MARK: - TokenManager

final class TokenManagerTests: XCTestCase {

    private let hour: TimeInterval = 3600

    func test_savedTokens_areReadBack() async throws {
        let manager = TokenManager(keychain: InMemoryKeychain(), keys: .auth)

        try await manager.saveTokens(
            accessToken: "access-1", accessTokenExpiration: Date().addingTimeInterval(hour),
            refreshToken: "refresh-1", refreshTokenExpiration: Date().addingTimeInterval(24 * hour))

        let access = try await manager.getAccessToken()
        let refresh = try await manager.getRefreshToken()
        XCTAssertEqual(access, "access-1")
        XCTAssertEqual(refresh, "refresh-1")
        let accessValid = await manager.hasValidAccessToken()
        let refreshValid = await manager.hasValidRefreshToken()
        XCTAssertTrue(accessValid)
        XCTAssertTrue(refreshValid)
    }

    /// `getAccessToken` ne regarde pas l'expiration : un jeton expiré est
    /// toujours rendu, et `AuthMiddleware` l'envoie tel quel. Seul
    /// `hasValidAccessToken` le sait expiré.
    func test_expiredAccessToken_isStillReturned_butNotValid() async throws {
        let manager = TokenManager(keychain: InMemoryKeychain(), keys: .auth)

        try await manager.saveTokens(
            accessToken: "expired", accessTokenExpiration: Date().addingTimeInterval(-hour),
            refreshToken: "refresh", refreshTokenExpiration: Date().addingTimeInterval(hour))

        let access = try await manager.getAccessToken()
        XCTAssertEqual(access, "expired")
        let accessValid = await manager.hasValidAccessToken()
        let refreshValid = await manager.hasValidRefreshToken()
        XCTAssertFalse(accessValid)
        XCTAssertTrue(refreshValid, "les deux expirations sont indépendantes")
    }

    func test_noTokens_meansNothingValid() async throws {
        let manager = TokenManager(keychain: InMemoryKeychain(), keys: .auth)

        let access = try await manager.getAccessToken()
        XCTAssertNil(access)
        let accessValid = await manager.hasValidAccessToken()
        let refreshValid = await manager.hasValidRefreshToken()
        XCTAssertFalse(accessValid)
        XCTAssertFalse(refreshValid)
    }

    func test_clear_removesEveryKey() async throws {
        let keychain = InMemoryKeychain()
        let manager = TokenManager(keychain: keychain, keys: .auth)
        try await manager.saveTokens(
            accessToken: "a", accessTokenExpiration: Date().addingTimeInterval(hour),
            refreshToken: "r", refreshTokenExpiration: Date().addingTimeInterval(hour))

        try await manager.clearTokens()

        let access = try await manager.getAccessToken()
        XCTAssertNil(access)
        let stored = await keychain.keys()
        XCTAssertTrue(stored.isEmpty, "restant : \(stored)")
    }

    /// Une écriture partielle ne laisse jamais un jeu de jetons incohérent.
    func test_failedSave_rollsBackEveryKey() async throws {
        let keychain = InMemoryKeychain(failingSaveNumber: 3)
        let manager = TokenManager(keychain: keychain, keys: .auth)

        do {
            try await manager.saveTokens(
                accessToken: "a", accessTokenExpiration: Date().addingTimeInterval(hour),
                refreshToken: "r", refreshTokenExpiration: Date().addingTimeInterval(hour))
            XCTFail("la troisième écriture devait échouer")
        } catch {}

        let stored = await keychain.keys()
        XCTAssertTrue(stored.isEmpty, "restant : \(stored)")
        let access = try await manager.getAccessToken()
        XCTAssertNil(access)
    }

    func test_corruptedExpiry_clearsTheTokens() async throws {
        let keychain = InMemoryKeychain()
        try await keychain.saveString("a", forKey: "auth.accessToken")
        try await keychain.saveString("not-a-date", forKey: "auth.accessTokenExpiration")
        try await keychain.saveString("r", forKey: "auth.refreshToken")
        try await keychain.saveString("not-a-date", forKey: "auth.refreshTokenExpiration")
        let manager = TokenManager(keychain: keychain, keys: .auth)

        let access = try await manager.getAccessToken()
        XCTAssertNil(access)
        let stored = await keychain.keys()
        XCTAssertTrue(stored.isEmpty, "restant : \(stored)")
    }

    /// L'auth de l'app et le chat partagent un Keychain mais pas leurs jetons.
    func test_authAndChatNamespaces_doNotShareTokens() async throws {
        let keychain = InMemoryKeychain()
        let auth = TokenManager(keychain: keychain, keys: .auth)
        let chat = TokenManager(keychain: keychain, keys: .chat)

        try await auth.saveTokens(
            accessToken: "app", accessTokenExpiration: Date().addingTimeInterval(hour),
            refreshToken: "app-r", refreshTokenExpiration: Date().addingTimeInterval(hour))

        let chatAccess = try await chat.getAccessToken()
        XCTAssertNil(chatAccess)

        try await chat.clearTokens()
        let appAccess = try await auth.getAccessToken()
        XCTAssertEqual(appAccess, "app", "vider le chat ne touche pas l'auth de l'app")
    }

    /// Une nouvelle instance relit le Keychain : les jetons survivent à un
    /// redémarrage de l'app.
    func test_tokens_surviveANewInstance() async throws {
        let keychain = InMemoryKeychain()
        try await TokenManager(keychain: keychain, keys: .auth).saveTokens(
            accessToken: "persisted", accessTokenExpiration: Date().addingTimeInterval(hour),
            refreshToken: "r", refreshTokenExpiration: Date().addingTimeInterval(hour))

        let reopened = TokenManager(keychain: keychain, keys: .auth)
        let access = try await reopened.getAccessToken()
        XCTAssertEqual(access, "persisted")
        let accessValid = await reopened.hasValidAccessToken()
        XCTAssertTrue(accessValid)
    }
}

// MARK: - JWTValidator

final class JWTValidatorTests: XCTestCase {

    private let validator = JWTValidator()

    func test_futureExpiry_isValid() {
        XCTAssertTrue(validator.isValid(token: makeJWT(["exp": Date().addingTimeInterval(3600).timeIntervalSince1970])))
    }

    func test_pastExpiry_isNotValid() {
        XCTAssertFalse(validator.isValid(token: makeJWT(["exp": Date().addingTimeInterval(-3600).timeIntervalSince1970])))
    }

    func test_missingExpiry_isNotValid() {
        XCTAssertFalse(validator.isValid(token: makeJWT(["sub": "user-1"])))
    }

    func test_malformedTokens_areNotValid() {
        XCTAssertFalse(validator.isValid(token: ""))
        XCTAssertFalse(validator.isValid(token: "only.two"))
        XCTAssertNil(validator.decodePayload("a.b.c.d"))
        XCTAssertNil(validator.decodePayload("header.%%%.signature"))
    }

    /// base64url sans remplissage, avec `-` et `_` : la forme réelle des JWT.
    func test_base64UrlPayloadWithoutPadding_isDecoded() throws {
        // Un `sub` choisi pour produire `-`/`_` et une longueur non multiple de 4.
        let token = makeJWT(["sub": "??>>~~", "n": 1])
        let payload = try XCTUnwrap(validator.decodePayload(token))
        XCTAssertEqual(payload["sub"] as? String, "??>>~~")
    }

    /// Décoder n'est pas vérifier : une signature quelconque est acceptée.
    /// L'autorisation reste au serveur (invariant 003).
    func test_signatureIsNotChecked() {
        let token = makeJWT(["exp": Date().addingTimeInterval(3600).timeIntervalSince1970], signature: "forged")
        XCTAssertTrue(validator.isValid(token: token))
    }

    private func makeJWT(_ claims: [String: Any], signature: String = "sig") -> String {
        func encode(_ object: Any) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encode(["alg": "HS256", "typ": "JWT"])).\(encode(claims)).\(signature)"
    }
}

// MARK: - APIClient face à un 401

final class UnauthorizedResponseTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func test_token_isSentAsBearer() async throws {
        StubURLProtocol.respond(status: 200, body: #"{"ok":true}"#)
        let client = await makeClient(accessToken: "token-A")

        let reply: Ping = try await client.request(endpoint: PingEndpoint())

        XCTAssertTrue(reply.ok)
        XCTAssertEqual(StubURLProtocol.authorizationHeaders(), ["Bearer token-A"])
    }

    /// Le comportement actuel, à changer quand IAM livrera le contrat de
    /// renouvellement : un seul rejeu, avec le même jeton, puis `unauthorized`.
    func test_401_isReplayedOnceWithTheSameToken_thenFails() async throws {
        StubURLProtocol.respond(status: 401, body: "{}")
        let client = await makeClient(accessToken: "token-A")

        do {
            let _: Ping = try await client.request(endpoint: PingEndpoint())
            XCTFail("un 401 doit remonter")
        } catch let error as APIError {
            XCTAssertTrue(error.isUnauthorized, "erreur reçue : \(error)")
        }

        XCTAssertEqual(StubURLProtocol.authorizationHeaders(), ["Bearer token-A", "Bearer token-A"],
                       "aucun renouvellement : le rejeu porte le même jeton")
    }

    func test_401_doesNotClearTheStoredTokens() async throws {
        StubURLProtocol.respond(status: 401, body: "{}")
        let tokens = TokenManager(keychain: InMemoryKeychain(), keys: .auth)
        try await tokens.saveTokens(
            accessToken: "token-A", accessTokenExpiration: Date().addingTimeInterval(3600),
            refreshToken: "r", refreshTokenExpiration: Date().addingTimeInterval(3600))
        let client = await makeClient(tokenManager: tokens)

        let _: Ping? = try? await client.request(endpoint: PingEndpoint())

        let access = try await tokens.getAccessToken()
        XCTAssertEqual(access, "token-A", "la fin de session est décidée ailleurs (SessionManager)")
    }

    // MARK: Fabrique

    private func makeClient(accessToken: String) async -> APIClient {
        let tokens = TokenManager(keychain: InMemoryKeychain(), keys: .auth)
        try? await tokens.saveTokens(
            accessToken: accessToken, accessTokenExpiration: Date().addingTimeInterval(3600),
            refreshToken: "refresh", refreshTokenExpiration: Date().addingTimeInterval(3600))
        return await makeClient(tokenManager: tokens)
    }

    private func makeClient(tokenManager: any TokenManagerProtocol) async -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return await APIClient.makeConfigured(
            baseURL: "https://session-renewal.test",
            session: URLSession(configuration: configuration),
            middlewares: [AuthMiddleware(tokenManager: tokenManager, logger: .shared)],
            circuitBreaker: CircuitBreakerServiceImpl(logger: .shared),
            logger: .shared,
            runTimeConfig: DeviceConfiguration(
                maxConcurrentRequests: 4, cacheSizeMB: 0, backgroundUpdates: false,
                retryProfile: .none, timeoutMultiplier: 1, minTimeout: 5, maxTimeout: 10),
            networkMonitor: AlwaysConnected(),
            performanceMonitor: QuietPerformanceMonitor(),
            policyResolver: AdaptivePolicyResolver(deviceTier: FixedDeviceTier())
        )
    }
}

// MARK: - Doublures

private struct Ping: Decodable { let ok: Bool }

private struct PingEndpoint: APIEndpoint, EndpointPolicyProviding {
    var path: String { "/api/test/ping" }
    var method: HTTPMethod { .get }
    var parameters: [String: Any]? { nil }
    var headers: [String: String]? { nil }
    var cachePolicy: EndpointCachePolicy { .noCache }
    var circuitBreakerProfile: CircuitBreakerProfile { .standard }
    var priority: RequestPriority { .medium }
    var isIdempotent: Bool { true }
    var timeoutPolicy: EndpointTimeoutPolicy { .standard }
    var rateLimitPolicy: RateLimitPolicy { .relaxed }
}

/// Keychain en mémoire. `failingSaveNumber` fait échouer la n-ième écriture.
private actor InMemoryKeychain: KeychainStoreProtocol {
    private var storage: [String: Data] = [:]
    private var saves = 0
    private let failingSaveNumber: Int?

    init(failingSaveNumber: Int? = nil) { self.failingSaveNumber = failingSaveNumber }

    func keys() -> [String] { storage.keys.sorted() }

    func saveString(_ value: String, forKey key: String) async throws {
        try await saveData(Data(value.utf8), forKey: key)
    }
    func getString(forKey key: String) async throws -> String? {
        storage[key].map { String(decoding: $0, as: UTF8.self) }
    }
    func saveData(_ data: Data, forKey key: String) async throws {
        saves += 1
        if saves == failingSaveNumber { throw CocoaError(.fileWriteUnknown) }
        storage[key] = data
    }
    func getData(forKey key: String) async throws -> Data? { storage[key] }
    func saveCodable<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        try await saveData(JSONEncoder().encode(value), forKey: key)
    }
    func getCodable<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        try storage[key].map { try JSONDecoder().decode(T.self, from: $0) }
    }
    func remove(forKey key: String) async throws { storage[key] = nil }
    func removeAll() async throws { storage.removeAll() }
}

private struct AlwaysConnected: NetworkMonitoringProtocol {
    func currentSnapshot() async -> NetworkSnapshot {
        NetworkSnapshot(timestamp: Date(), status: .wifi, isExpensive: false, isConstrained: false, isReachable: true)
    }
    var isConnected: Bool { get async { true } }
}

private struct QuietPerformanceMonitor: PerformanceMonitorProtocol {
    func getSnapshot() async -> PerformanceSnapshot {
        PerformanceSnapshot(timestamp: Date(), metrics: PerformanceMetrics(
            memory: MemorySnapshot(usedMB: 100, availableMB: 1000, totalMB: 1100),
            cpuUsage: 0.1,
            battery: BatteryStatus(level: 1, isCharging: true),
            thermalState: .nominal))
    }
    func criticalEvents() -> AsyncStream<PerformanceEvent> { AsyncStream { $0.finish() } }
}

private struct FixedDeviceTier: DeviceTierProtocol {
    func getDeviceTier() async -> DeviceTierSnapshot { .premium }
}

/// Répond à toutes les requêtes avec le même statut, et retient chacune.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = Data()
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static func respond(status: Int, body: String) {
        lock.lock(); defer { lock.unlock() }
        self.status = status
        self.body = Data(body.utf8)
    }

    static func authorizationHeaders() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return seen.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        status = 200; body = Data(); seen = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.seen.append(request)
        let status = Self.status, body = Self.body
        Self.lock.unlock()

        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
