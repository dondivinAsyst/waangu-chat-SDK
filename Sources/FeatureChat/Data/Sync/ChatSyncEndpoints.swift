// MARK: - FeatureChat/Data/Endpoints/HTTPChatSyncEndpoints.swift
//
// Module  : FeatureChat
// Rôle    : Endpoints de synchro du chat.
//           Même pattern que HTTPAuthEndpoints.

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

// MARK: - HTTPChatSyncEndpoints

public enum HTTPChatSyncEndpoints: APIEndpoint, EndpointPolicyProviding {

    case flushOutbox(ChatOutboxBatchRequestDTO)
    case pullEvents(since: Date, cursor: String?, limit: Int)
    case inboxSummary
    case conversationMessages(conversationId: String, since: Date?, limit: Int)

    // MARK: - APIEndpoint

    public var path: String {
        switch self {
        case .flushOutbox:
            return "/api/v1/chat/sync/outbox"
        case .pullEvents:
            return "/api/v1/chat/sync/events"
        case .inboxSummary:
            return "/api/v1/chat/sync/inbox"
        case .conversationMessages(let convId, _, _):
            return "/api/v1/chat/sync/conversation/\(convId)/messages"
        }
    }

    public var method: HTTPMethod {
        switch self {
        case .flushOutbox:                                      return .post
        case .pullEvents, .inboxSummary, .conversationMessages: return .get
        }
    }

    public var parameters: [String: Any]? {
        switch self {
        case .flushOutbox(let request):
            return try? request.toDictionary()
        case .pullEvents(let since, let cursor, let limit):
            var params: [String: Any] = [
                "since": ISO8601DateFormatter().string(from: since),
                "limit": limit
            ]
            if let cursor { params["cursor"] = cursor }
            return params
        case .inboxSummary:
            return nil
        case .conversationMessages(_, let since, let limit):
            var params: [String: Any] = ["limit": limit]
            if let since {
                params["since"] = ISO8601DateFormatter().string(from: since)
            }
            return params
        }
    }

    public var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }

    // MARK: - EndpointPolicyProviding

    public var cachePolicy: EndpointCachePolicy {
        switch self {
        case .flushOutbox:          return .noCache
        case .pullEvents:           return .noCache
        case .inboxSummary:         return .noCache
        case .conversationMessages: return .noCache
        }
    }

    public var circuitBreakerProfile: CircuitBreakerProfile {
        switch self {
        case .inboxSummary:         return .aggressive
        case .flushOutbox:          return .standard
        case .conversationMessages: return .standard
        case .pullEvents:           return .conservative
        }
    }

    public var priority: RequestPriority {
        switch self {
        case .inboxSummary:         return .critical
        case .flushOutbox:          return .high
        case .conversationMessages: return .high
        case .pullEvents:           return .medium
        }
    }

    public var timeoutPolicy: EndpointTimeoutPolicy {
        switch self {
        case .inboxSummary:         return .fast
        case .conversationMessages: return .fast
        case .flushOutbox:          return .standard
        case .pullEvents:           return .standard
        }
    }

    public var isIdempotent: Bool {
        true  // flush = idempotencyKey côté serveur, GET = toujours idempotent
    }

    public var rateLimitPolicy: RateLimitPolicy {
        switch self {
        case .flushOutbox: return .standard
        case .pullEvents, .inboxSummary, .conversationMessages: return .relaxed
        }
    }
}
