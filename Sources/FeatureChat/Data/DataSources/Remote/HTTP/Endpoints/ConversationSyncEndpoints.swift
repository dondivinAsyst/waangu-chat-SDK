//
//  ConversationSyncEndpoints.swift
//  FeatureChat
//
//  Endpoints for conversation synchronization
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

// MARK: - Conversation Sync Endpoints

public enum ConversationSyncEndpoints: APIEndpoint, EndpointPolicyProviding {
    
    case syncConversations(since: Date?, limit: Int)
    case syncConversationMessages(conversationId: String, since: Date?, limit: Int)
    
    // MARK: - APIEndpoint
    
    public var path: String {
        switch self {
        case .syncConversations:
            return "/api/v1/me/conversations/sync"
        case .syncConversationMessages(let conversationId, _, _):
            return "/api/v1/me/conversations/\(conversationId)/feed/sync"
        }
    }
    
    public var method: HTTPMethod {
        .get
    }
    
    public var parameters: [String: Any]? {
        switch self {
        case .syncConversations(let since, let limit):
            var params: [String: Any] = ["limit": limit]
            if let since {
                params["since"] = ISO8601DateFormatter().string(from: since)
            }
            return params
            
        case .syncConversationMessages(_, let since, let limit):
            var params: [String: Any] = ["limit": limit]
            if let since {
                params["since"] = ISO8601DateFormatter().string(from: since)
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
        .noCache  // Always fetch fresh conversation data
    }
    
    public var circuitBreakerProfile: CircuitBreakerProfile {
        .standard
    }
    
    public var priority: RequestPriority {
        .high  // Conversation sync is important for UX
    }
    
    public var timeoutPolicy: EndpointTimeoutPolicy {
        switch self {
        case .syncConversations:       return .standard
        case .syncConversationMessages: return .standard
        }
    }
    
    public var isIdempotent: Bool {
        true  // GET is always idempotent
    }
    
    public var rateLimitPolicy: RateLimitPolicy {
        .relaxed  // Allow frequent syncs
    }
}
