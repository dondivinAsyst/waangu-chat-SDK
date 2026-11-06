import Foundation
import WaanguCoreKit
import WaanguNetworkKit

enum ContactsEndpoints: APIEndpoint, EndpointPolicyProviding {
    case getContacts(ContactRequest)
    case blockOrUnblockContact(BlockContactRequest)
    case updateMyProfile(myProfileUpdateReq)
  
    var path: String {
        switch self {
        case .getContacts:
            return "/identity/contacts/sync"
        case .blockOrUnblockContact:
            return "/identity/contacts/block"
        case .updateMyProfile:
            return "/identity/users/\(CurrentUser.shared.id)"
        }
    }
        
    var method: HTTPMethod {
        switch self {
        case .getContacts, .blockOrUnblockContact:
            return .post
        case .updateMyProfile:
            return .put
        }
    }
    
    var parameters: [String: Any]? {
        switch self {
        case .getContacts(let request):
            // POST → encode body
            return (try? request.toDictionary()) ?? [:]
        case .blockOrUnblockContact(let request):
            return (try? request.toDictionary()) ?? [:]
        case .updateMyProfile(let req):
            return(try? req.toDictionary()) ?? [:]
        }
    }
    
    var headers: [String: String]? {
        return [
            "X-Correlation-Id": CorrelationId().value,  // B59 — même règle que ChatFinanceEndpoints
            "accept": "application/json",
            "x-chat-session": CurrentSessionInfo.shared.sessionId,
            "Content-Type": "application/json"
        ]
    }
}
extension ContactsEndpoints {
    var cachePolicy: EndpointCachePolicy { .noCache }

    var circuitBreakerProfile: CircuitBreakerProfile { .standard }

    var priority: RequestPriority { .medium }

    var timeoutPolicy: EndpointTimeoutPolicy { .standard }

    var isIdempotent: Bool { true }

    var rateLimitPolicy: RateLimitPolicy { .standard }
}
