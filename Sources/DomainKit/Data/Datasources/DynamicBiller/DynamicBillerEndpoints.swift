//
//  DynamicBillerEndpoints.swift
//  AppModules
//
//  Created by Asyst on 4/14/26.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

enum DynamicBillerEndpoints: APIEndpoint, EndpointPolicyProviding {
    case getBillerFormParams(BillerFormRequestDTO)
    case getBillerCategories
    /// URL absolue ou relative fournie par le backend (`fetchFieldForm`).
    case fetchFieldForm(url: String, httpMethod: HTTPMethod, body: [String: String])
    
    var path: String {
        switch self {
        case .getBillerFormParams:
            return "/api/billerForm/getParams"
        case .getBillerCategories:
            return "/api/biller/getBillerCategories"
        case .fetchFieldForm(let url, _, _):
            return url
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .getBillerFormParams, .getBillerCategories:
            return .post
        case .fetchFieldForm(_, let httpMethod, _):
            return httpMethod
        }
    }
    
    var parameters: [String: Any]? {
        switch self {
        case .getBillerFormParams(let request):
            return try? request.toDictionary()
        case .getBillerCategories:
            return ["group": ""]
        case .fetchFieldForm(_, _, let body):
            return body.isEmpty ? nil : body.mapValues { $0 as Any }
        }
    }
    
    var headers: [String: String]? {
        [:]
    }
}

extension DynamicBillerEndpoints {
    var cachePolicy: EndpointCachePolicy {
        switch self {
        case .getBillerFormParams:
            return .noCache
        case .getBillerCategories:
            return .noCache
        case .fetchFieldForm:
            return .noCache
        }
    }

    var circuitBreakerProfile: CircuitBreakerProfile {
        switch self {
        case .getBillerFormParams:
            return .aggressive
        case .getBillerCategories:
            return .standard
        case .fetchFieldForm:
            return .standard
        }
    }

    var priority: RequestPriority {
        switch self {
        case .getBillerFormParams, .getBillerCategories:
            return .high
        case .fetchFieldForm:
            return .high
        }
    }
    
    var timeoutPolicy: EndpointTimeoutPolicy {
        switch self {
        case .getBillerFormParams, .getBillerCategories:
            return .standard
        case .fetchFieldForm:
            return .standard
        }
    }

    var isIdempotent: Bool {
        switch self {
        case .getBillerFormParams, .getBillerCategories:
            return true
        case .fetchFieldForm:
            return true
        }
    }
    
    var rateLimitPolicy: RateLimitPolicy {
        switch self {
        case .getBillerFormParams, .getBillerCategories:
            return .standard
        case .fetchFieldForm:
            return .standard
        }
    }
}
