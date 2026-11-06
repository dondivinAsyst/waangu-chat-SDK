//
//  ChatLoginAppIdTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 1.9 — l'identifiant de l'application que le Chat envoie à Identity
//  (`X-App-Id`) vient de l'hôte. C'était un littéral dans ce paquet : toute application
//  qui l'utilisait se présentait comme Waangu User.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class ChatLoginAppIdTests: XCTestCase {

    private func sentHeaders(appId: String) async -> [String: String]? {
        let client = RecordingAuthClient()
        let source = HTTPAuthDataSource(apiClient: client, appId: appId, logger: QuietLogger())
        let request = AuthRequest.mapper(deviceInfo: DeviceContext(
            deviceId: "d", deviceModel: "m", brandName: "Apple", manufacturer: "Apple",
            osVersion: "18.0", appVersion: "1.0", buildNumber: "1", platformOS: "iOS"))

        _ = try? await source.authenticate(request)
        return client.headers
    }

    func test_theHostsAppId_isSentAsXAppId() async {
        let headers = await sentHeaders(appId: "app-doctor")

        XCTAssertEqual(headers?["X-App-Id"], "app-doctor")
    }

    func test_twoHosts_sendTheirOwnIds() async {
        let first = await sentHeaders(appId: "app-user")
        let second = await sentHeaders(appId: "app-driver")

        XCTAssertEqual(first?["X-App-Id"], "app-user")
        XCTAssertEqual(second?["X-App-Id"], "app-driver")
    }

    func test_theOtherLoginHeaders_areUnchanged() async {
        let headers = await sentHeaders(appId: "any")

        XCTAssertEqual(headers?["Content-Type"], "application/json")
        XCTAssertEqual(headers?["accept"], "application/json")
        XCTAssertNotNil(headers?["X-Correlation-Id"])
    }
}

private final class RecordingAuthClient: APIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _headers: [String: String]?
    var headers: [String: String]? { lock.withLock { _headers } }

    struct Stop: Error {}

    var isConnected: Bool { get async { true } }
    func request<T: Decodable>(endpoint: any APIEndpoint) async throws -> T {
        lock.withLock { _headers = endpoint.headers }
        throw Stop()
    }
    func cancelRequest(for endpoint: any APIEndpoint) async {}
    func cancelAllRequests() async {}
    func getPerformanceMetrics() async -> APIPerformanceMetrics {
        APIPerformanceMetrics(totalRequests: 0, successCount: 0, failureCount: 0, averageDuration: 0,
                              rateLimitedCount: 0, circuitBreakerBlockCount: 0)
    }
}

private struct QuietLogger: AppLoggerProtocol {
    func log(_ message: String, level: LogLevel, file: String, function: String, line: Int) async {}
    func addObserver(_ observer: any LogObserverProtocol) async {}
    func removeAllObservers() async {}
    var minLevel: LogLevel { get async { .debug } }
}
