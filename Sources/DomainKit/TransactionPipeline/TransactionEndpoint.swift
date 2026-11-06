import Foundation
import WaanguCoreKit
import WaanguNetworkKit

/// Generic endpoint for any transaction pipeline step.
///
/// Replaces feature-specific endpoint enums (e.g. `SendMoneyEndpoints`,
/// `MoveMoneyEndpoints`) that all pointed to the same `/api/transaction/*` paths.
struct TransactionEndpoint<Body: Encodable & Sendable>: APIEndpoint, EndpointPolicyProviding {

    let step: TransactionStep
    let body: Body
    let stepPolicy: TransactionStepPolicy

    // MARK: - APIEndpoint

    var path: String { step.path }
    var method: HTTPMethod { .post }
    var parameters: [String: Any]? { try? body.toDictionary() }
    var headers: [String: String]? { ["Content-Type": "application/json"] }

    // MARK: - EndpointPolicyProviding

    var cachePolicy: EndpointCachePolicy { .noCache }

    var circuitBreakerProfile: CircuitBreakerProfile {
        switch stepPolicy {
        case .standard: .standard
        case .critical: .aggressive
        }
    }

    var priority: RequestPriority {
        switch stepPolicy {
        case .standard: .high
        case .critical: .critical
        }
    }

    var timeoutPolicy: EndpointTimeoutPolicy {
        switch stepPolicy {
        case .standard: .standard
        case .critical: .fast
        }
    }

    var isIdempotent: Bool { false }

    var rateLimitPolicy: RateLimitPolicy {
        switch stepPolicy {
        case .standard: .standard
        case .critical: .strict
        }
    }
}
