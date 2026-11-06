//
//  AcceptLanguageTests.swift
//  NetworkKitTests
//

import XCTest
import WaanguCoreKit
@testable import WaanguNetworkKit

/// `Accept-Language`: `en` by default, the endpoint's own value when it declares one.
final class AcceptLanguageTests: XCTestCase {

    /// Wallet APIs keep `en` — they behave strangely with any other value.
    func test_endpointWithoutLanguage_getsEnglish() {
        XCTAssertEqual(AuthMiddleware.defaultLanguage(for: LanguageEndpoint(headers: nil)), "en")
        XCTAssertEqual(AuthMiddleware.defaultLanguage(for: LanguageEndpoint(headers: ["Accept": "application/json"])), "en")
    }

    /// Chat Core declares the app language; overwriting it sent `en` for every user.
    func test_endpointDeclaringALanguage_keepsIt() {
        XCTAssertNil(AuthMiddleware.defaultLanguage(for: LanguageEndpoint(headers: ["Accept-Language": "fr"])))
    }
}

private struct LanguageEndpoint: APIEndpoint, EndpointPolicyProviding {
    let headers: [String: String]?
    var path: String { "/test" }
    var method: HTTPMethod { .get }
    var parameters: [String: Any]? { nil }
    var cachePolicy: EndpointCachePolicy { .noCache }
    var circuitBreakerProfile: CircuitBreakerProfile { .standard }
    var priority: RequestPriority { .medium }
    var isIdempotent: Bool { true }
    var timeoutPolicy: EndpointTimeoutPolicy { .standard }
    var rateLimitPolicy: RateLimitPolicy { .none }
}
