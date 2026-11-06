//
//  AuthEndpoints.swift
//  AppModules
//
//  Created by Don divin on 5/20/26.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

enum AuthChatEndpoint: APIEndpoint, EndpointPolicyProviding {
    case authenticate(request: AuthRequest, appId: String)
   
    var path: String {
        switch self {
        case .authenticate:
            return "/identity/chat/auth/chat-login"
        default : return ""
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .authenticate: return .post
        default: return .get
        }
    }
    
    var parameters: [String: Any]? {
        switch self {
        case let .authenticate(auth, _):
            do {
                return try auth.toDictionary()
            } catch {
                debugLog("❌ Failed to convert auth to dictionary: \(error)")
                // You can also log this to Crashlytics / Sentry
                return nil
            }
        }
    }
    
    var headers: [String: String]? {
        switch self {
        case let .authenticate(_, appId ):
            return [
                "X-Correlation-Id": CorrelationId().value,  // B59 — même règle que ChatFinanceEndpoints
                "accept": "application/json",
                "X-App-Id": appId,
//                "Authorization": "Bearer \(token)",
//                "x-chat-session":sessionId,
                "Content-Type": "application/json"
            ]
        }
    }
    
}
extension AuthChatEndpoint {
    var cachePolicy: EndpointCachePolicy { .noCache }

    var circuitBreakerProfile: CircuitBreakerProfile { .standard }

    var priority: RequestPriority { .medium }

    var timeoutPolicy: EndpointTimeoutPolicy { .standard }

    var isIdempotent: Bool { true }

    var rateLimitPolicy: RateLimitPolicy { .relaxed }
}

extension AuthChatEndpoint: ChatSessionHeaderPolicyProviding {
    var requiresChatSessionHeader: Bool { false }
}
