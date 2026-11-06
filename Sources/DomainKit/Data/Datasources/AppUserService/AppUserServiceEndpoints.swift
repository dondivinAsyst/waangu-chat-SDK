//
//  Endpoints.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

enum AppUserServiceEndpoints: APIEndpoint, EndpointPolicyProviding {
    
    case getServiceList(
        request : AppUserServiceRequestDTO,
        forcedRefresh: Bool
    )
    
    var path: String {
        switch self {
        case .getServiceList:
            return "/api/service/listAllServices"
        }
    }
      
    var method: HTTPMethod {
        switch self {
        case .getServiceList:
            return .post
        }
    }
    
    var parameters: [String: Any]? {
        switch self {
        case .getServiceList(let request, _):
            return try? request.toDictionary()
        }
    }
    
    var headers: [String: String]? {
        return ["Content-Type": "application/json"]
    }
}

extension AppUserServiceEndpoints {

    var cachePolicy: EndpointCachePolicy {
        switch self {
            
        case .getServiceList(let request, let forcedRefresh):
            if forcedRefresh {
                return .noCache
            } else {
                return .alwaysUseCache(ttl: 2000)
            }
        }
        
    }

    var circuitBreakerProfile: CircuitBreakerProfile {
        switch self {
        case .getServiceList:
            return .standard
        }
    }

    var priority: RequestPriority {
        switch self {
        case .getServiceList:
            return .high
        }
    }
    
    var timeoutPolicy: EndpointTimeoutPolicy {
        switch self {
        case .getServiceList:
            return .standard
        }
    }

    var isIdempotent: Bool {
        switch self {
        case .getServiceList:
            return true
        }
    }
    
    var rateLimitPolicy: RateLimitPolicy {
        return .standard
    }
}
