import Foundation
import WaanguCoreKit
import WaanguNetworkKit

enum StatusEndpoints: APIEndpoint {
    case getContactStatus
    case onPostStatus(CreateStatusRequest)
    case deleteStatus(DeleteStatusRequest)
    case syncStories(since: Date?, limit: Int)

    var path: String {
        switch self {
        case .getContactStatus, .onPostStatus, .deleteStatus:
            return "/chat-core/stories"
        case .syncStories:
            return "/api/v1/me/stories/sync"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getContactStatus, .syncStories:
            return .get
        case .onPostStatus:
            return .post
        case .deleteStatus:
            return .delete
        }
    }

    var parameters: [String: Any]? {
        switch self {
        case .getContactStatus:
            return nil
        case .syncStories(let since, let limit):
            var params: [String: Any] = ["limit": limit]
            if let since = since {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                params["since"] = formatter.string(from: since)
            }
            return params
        case .onPostStatus(let request):
            return (try? request.toDictionary()) ?? [:]
        case .deleteStatus(let request):
            return (try? request.toDictionary()) ?? [:]
        }
    }

    var headers: [String: String]? {
        [
            "X-Correlation-Id": CorrelationId().value,  // B59 — même règle que ChatFinanceEndpoints
            "Content-Type": "application/json",
            "Accept": "application/json",
            "x-chat-session": CurrentSessionInfo.shared.sessionId
        ]
    }
}

extension StatusEndpoints: EndpointPolicyProviding {
    var cachePolicy: EndpointCachePolicy { .noCache }

    var circuitBreakerProfile: CircuitBreakerProfile { .standard }

    var priority: RequestPriority { .medium }

    var timeoutPolicy: EndpointTimeoutPolicy { .standard }

    var isIdempotent: Bool {
        switch self {
        case .getContactStatus, .deleteStatus, .syncStories:
            return true
        case .onPostStatus:
            return false
        }
    }

    var rateLimitPolicy: RateLimitPolicy { .standard }
}
