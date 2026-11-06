//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit



enum LocationEndpoints: APIEndpoint, EndpointPolicyProviding {
    
    case findLocation(FindLocationRequestDTO)
    
    var path: String {
        switch self {
        case .findLocation:
            return "/api/location/findLocation"
        }
    }
      
    var method: HTTPMethod {
        switch self {
        case .findLocation :
            return .post
        }
    }
    
    var parameters: [String: Any]? {
        switch self {
        case .findLocation(let dto):
            return try? dto.toDictionary()
        }
    }
    
    var headers: [String: String]? {
        return ["Content-Type": "application/json"]
    }
}

extension LocationEndpoints {
    
    var cachePolicy: EndpointCachePolicy {
        switch self {
        case .findLocation(_) :
            return .noCache
        }
    }

    var circuitBreakerProfile: CircuitBreakerProfile {
        switch self {
        case .findLocation:
            return .standard
        }
    }

    var priority: RequestPriority {
        switch self {
        case .findLocation :
            return .high
        }
    }
    
    var timeoutPolicy: EndpointTimeoutPolicy {
        switch self {
        case .findLocation:
            return .standard

        }
    }

    var isIdempotent: Bool {
        switch self {
        case .findLocation:
            return true
      
        }
    }
    
    var rateLimitPolicy: RateLimitPolicy {
        switch self {
        case .findLocation:
            return .standard
      
        }
    }
}
