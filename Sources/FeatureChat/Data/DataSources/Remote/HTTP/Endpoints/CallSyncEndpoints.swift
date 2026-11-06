//
//  CallSyncEndpoints.swift
//  FeatureChat
//
//  Endpoints for call history synchronization
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

// MARK: - Call Sync Endpoints

public enum CallSyncEndpoints: APIEndpoint, EndpointPolicyProviding {

    case syncCalls(since: Date?, limit: Int)

    // MARK: - APIEndpoint

    public var path: String {
        switch self {
        case .syncCalls:
            return "/api/v1/me/calls/sync"
        }
    }

    public var method: HTTPMethod {
        .get
    }

    public var parameters: [String: Any]? {
        switch self {
        case .syncCalls(let since, let limit):
            var params: [String: Any] = ["limit": limit]
            // Omitted on the first ever sync — no `since` means "everything".
            if let since {
                params["since"] = LenientISO8601.string(from: since)
            }
            return params
        }
    }

    public var headers: [String: String]? {
        return [
            "X-Correlation-Id": CorrelationId().value,  // B59 — même règle que ChatFinanceEndpoints
            "accept": "application/json",
            "x-chat-session": CurrentSessionInfo.shared.sessionId,
            "Content-Type": "application/json"
        ]
    }

    // MARK: - EndpointPolicyProviding

    public var cachePolicy: EndpointCachePolicy {
        .noCache
    }

    public var circuitBreakerProfile: CircuitBreakerProfile {
        .standard
    }

    /// The Calls tab is secondary to the chat list — it can wait behind it.
    public var priority: RequestPriority {
        .medium
    }

    public var timeoutPolicy: EndpointTimeoutPolicy {
        .standard
    }

    public var isIdempotent: Bool {
        true
    }

    public var rateLimitPolicy: RateLimitPolicy {
        .relaxed
    }
}
