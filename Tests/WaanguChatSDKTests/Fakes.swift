//
//  Fakes.swift
//  WaanguChatSDKTests
//

import Foundation
import WaanguCoreKit
import WaanguFeatureChat

/// Chat tokens whose presence and value the test decides.
actor ScriptedChatTokens: ChatTokenManagerProtocol {
    private let accessValid: Bool
    private let refreshValid: Bool
    private let token: String?

    init(accessValid: Bool, refreshValid: Bool, token: String?) {
        self.accessValid = accessValid
        self.refreshValid = refreshValid
        self.token = token
    }

    func saveTokens(accessToken: String, accessTokenExpiration: Date,
                    refreshToken: String, refreshTokenExpiration: Date) async throws {}
    func clearTokens() async throws {}
    func getAccessToken() async throws -> String? { token }
    func getRefreshToken() async throws -> String? { token }
    func hasValidAccessToken() async -> Bool { accessValid }
    func hasValidRefreshToken() async -> Bool { refreshValid }
}

/// An API client that answers every request with the same decoded value, or throws.
final class StubAPIClient: APIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests = 0
    private var _cancelAll = 0
    private let connected: Bool
    private let response: Any?
    private let failure: Error?

    var requestCount: Int { lock.withLock { _requests } }
    var cancelAllCount: Int { lock.withLock { _cancelAll } }

    init(connected: Bool = true, response: Any? = nil, failure: Error? = nil) {
        self.connected = connected
        self.response = response
        self.failure = failure
    }

    var isConnected: Bool { get async { connected } }

    func request<T: Decodable>(endpoint: any APIEndpoint) async throws -> T {
        lock.withLock { _requests += 1 }
        if let failure { throw failure }
        guard let value = response as? T else {
            throw StubError.noAnswerOfThatType
        }
        return value
    }

    func cancelRequest(for endpoint: any APIEndpoint) async {}
    func cancelAllRequests() async { lock.withLock { _cancelAll += 1 } }

    func getPerformanceMetrics() async -> APIPerformanceMetrics {
        APIPerformanceMetrics(totalRequests: 7, successCount: 5, failureCount: 2,
                              averageDuration: 0.5, rateLimitedCount: 0, circuitBreakerBlockCount: 0)
    }
}

enum StubError: Error, LocalizedError, Equatable {
    case noAnswerOfThatType
    case unreachable

    var errorDescription: String? {
        switch self {
        case .noAnswerOfThatType: return "no answer of that type"
        case .unreachable: return "server unreachable"
        }
    }
}

/// The host's own login tokens. Nothing here reaches the Keychain.
actor HostTokens: TokenManagerProtocol {
    func saveTokens(accessToken: String, accessTokenExpiration: Date,
                    refreshToken: String, refreshTokenExpiration: Date) async throws {}
    func clearTokens() async throws {}
    func getAccessToken() async throws -> String? { "host-token" }
    func getRefreshToken() async throws -> String? { "host-refresh" }
    func hasValidAccessToken() async -> Bool { true }
    func hasValidRefreshToken() async -> Bool { true }
}

/// A keychain in memory: package unit tests have no Keychain entitlement (error -34018).
actor MemoryKeychain: KeychainStoreProtocol {
    private var storage: [String: Data] = [:]

    func storedKeys() -> [String] { storage.keys.sorted() }

    func saveString(_ value: String, forKey key: String) async throws { storage[key] = Data(value.utf8) }
    func getString(forKey key: String) async throws -> String? {
        storage[key].map { String(decoding: $0, as: UTF8.self) }
    }
    func saveData(_ data: Data, forKey key: String) async throws { storage[key] = data }
    func getData(forKey key: String) async throws -> Data? { storage[key] }
    func saveCodable<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        storage[key] = try JSONEncoder().encode(value)
    }
    func getCodable<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        try storage[key].map { try JSONDecoder().decode(T.self, from: $0) }
    }
    func remove(forKey key: String) async throws { storage[key] = nil }
    func removeAll() async throws { storage.removeAll() }
}
