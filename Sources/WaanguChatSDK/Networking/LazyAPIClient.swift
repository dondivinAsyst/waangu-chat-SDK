//
//  LazyAPIClient.swift
//  WaanguChatSDK
//
//  Moved from the Waangu app target into WaanguChatSDK (SDK plan, step 1.9), where it was
//  `ChatAPIClientProxy` and was tied to the app's dependency container.
//

import Foundation
import WaanguCoreKit

/// An API client that is created when a call needs it. Creating the chat client is asynchronous,
/// and sync and outbox flush are built before that can happen.
///
/// Every call asks `make` for the client, so it answers with whatever client is current.
/// When `make` throws, requests throw the same error and the read-only calls answer with a neutral
/// value (not connected, empty metrics, nothing to cancel).
public final class LazyAPIClient: APIClientProtocol, @unchecked Sendable {

    private let make: @Sendable () async throws -> any APIClientProtocol

    public init(make: @escaping @Sendable () async throws -> any APIClientProtocol) {
        self.make = make
    }

    public var isConnected: Bool {
        get async { await (try? make())?.isConnected ?? false }
    }

    public func request<T: Decodable>(endpoint: any APIEndpoint) async throws -> T {
        try await (try await make()).request(endpoint: endpoint)
    }

    public func cancelRequest(for endpoint: any APIEndpoint) async {
        await (try? await make())?.cancelRequest(for: endpoint)
    }

    public func cancelAllRequests() async {
        await (try? await make())?.cancelAllRequests()
    }

    public func getPerformanceMetrics() async -> APIPerformanceMetrics {
        await (try? await make())?.getPerformanceMetrics()
            ?? APIPerformanceMetrics(
                totalRequests: 0,
                successCount: 0,
                failureCount: 0,
                averageDuration: 0,
                rateLimitedCount: 0,
                circuitBreakerBlockCount: 0
            )
    }
}
