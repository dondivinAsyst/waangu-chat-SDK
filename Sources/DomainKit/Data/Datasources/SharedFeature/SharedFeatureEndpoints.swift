//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit



enum SharedFeatureEndpoints: APIEndpoint, EndpointPolicyProviding {
    
    case getBalance(forceRefresh:Bool)
    case checkRecipientPhone(CheckCustomerPhoneRequestDTO)
    case getUserInfos
    case countNewNotifications
    
    var path: String {
        switch self {
        case .getBalance(_):
            return "/api/user/getBalance"
        case .checkRecipientPhone:
            return "/api/request/checkphone"
        case .getUserInfos:
            return "/api/user/getProfile"
        case .countNewNotifications:
            return "/api/notification/countNewNotification"
        }
    }
      
    var method: HTTPMethod {
        switch self {
        case .getBalance, .checkRecipientPhone, .getUserInfos, .countNewNotifications:
            return .post
        }
    }
    
    var parameters: [String: Any]? {
        switch self {
        case .getBalance:
            return [:]
        case .checkRecipientPhone(let dto):
            return try? dto.toDictionary()
        case .getUserInfos:
            return [:]
        case .countNewNotifications:
            return [:]
        }
    }
    
    var headers: [String: String]? {
        return ["Content-Type": "application/json"]
    }
}

extension SharedFeatureEndpoints {
    
    var cachePolicy: EndpointCachePolicy {
        switch self {
        case .getBalance(let forceRefresh):
            return forceRefresh
                ? .noCache
                : .alwaysUseCache(ttl: 300)
        case .checkRecipientPhone(_) :
            return .noCache
        case .getUserInfos:
            return .alwaysUseCache(ttl: 3600)
        case .countNewNotifications:
              return  .noCache
        }
    }

    var circuitBreakerProfile: CircuitBreakerProfile {
        switch self {
        case .getBalance, .checkRecipientPhone, .getUserInfos:
            return .standard
        case .countNewNotifications:
            return .aggressive
        }
    }

    var priority: RequestPriority {
        switch self {
        case .getBalance :
            return .high
        case .checkRecipientPhone, .getUserInfos:
            return .high
        case .countNewNotifications:
            return .critical
        }
    }
    
    var timeoutPolicy: EndpointTimeoutPolicy {
        switch self {
        case .getBalance, .checkRecipientPhone, .getUserInfos:
            return .standard
            
        case .countNewNotifications:
            return .fast

        }
    }

    var isIdempotent: Bool {
        switch self {
        case .getBalance, .checkRecipientPhone, .getUserInfos, .countNewNotifications:
            return true
      
        }
    }
    
    var rateLimitPolicy: RateLimitPolicy {
        switch self {
        case .getBalance, .checkRecipientPhone, .getUserInfos:
            return .standard
            
        case .countNewNotifications:
            return .strict
      
        }
    }
}
