//
//  FeatureCatalogEndpoints.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit



enum FeatureCatalogEndpoints: APIEndpoint, EndpointPolicyProviding {
    
    case getFeatureCatalog(forceRefresh:Bool)
    case getFeatureCatalogVersion(FeatureCatalogVersionRequestDTO)
    
    var path: String {
        switch self {
        case .getFeatureCatalog(_):
            return "/api/homeIcon/getHomeIcons"
        case .getFeatureCatalogVersion:
            return "api/homeIcon/getVersion"
        }
    }
      
    var method: HTTPMethod {
        switch self {
        case .getFeatureCatalog, .getFeatureCatalogVersion:
            return .post
        }
    }
    
    var parameters: [String: Any]? {
        switch self {
        case .getFeatureCatalog:
            return [:]
        case .getFeatureCatalogVersion(let request):
            return try? request.toDictionary()
        }
    }
    
    var headers: [String: String]? {
        return ["Content-Type": "application/json"]
    }
}

extension FeatureCatalogEndpoints {
    
    var cachePolicy: EndpointCachePolicy {
        switch self {
        case .getFeatureCatalog(let forceRefresh):
            return .noCache
        case .getFeatureCatalogVersion(_):
            return .noCache
        }
    }

    var circuitBreakerProfile: CircuitBreakerProfile {
        switch self {
        case .getFeatureCatalog:
            return .standard
        case .getFeatureCatalogVersion:
            return .aggressive
        }
    }

    var priority: RequestPriority {
        switch self {
        case .getFeatureCatalog, .getFeatureCatalogVersion :
            return .high
        
        }
    }
    
    var timeoutPolicy: EndpointTimeoutPolicy {
        switch self {
        case .getFeatureCatalog, .getFeatureCatalogVersion :
            return .standard

        }
    }

    var isIdempotent: Bool {
        switch self {
        case .getFeatureCatalog, .getFeatureCatalogVersion :
            return true
      
        }
    }
    
    var rateLimitPolicy: RateLimitPolicy {
        switch self {
        case .getFeatureCatalog, .getFeatureCatalogVersion :
            return .standard
      
        }
    }
}
