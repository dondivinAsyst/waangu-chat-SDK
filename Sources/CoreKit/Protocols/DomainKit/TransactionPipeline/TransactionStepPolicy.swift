import Foundation

/// Predefined policy profiles for transaction steps.
///
/// Maps to concrete NetworkKit policies (circuit breaker, priority, timeout,
/// rate limit) inside `TransactionGateway`, keeping CoreKit free of
/// NetworkKit dependencies.
public enum TransactionStepPolicy: Sendable {
    /// Default: standard circuit breaker, high priority, standard timeout.
    case standard
    /// Financial-critical: aggressive circuit breaker, critical priority,
    /// fast timeout, strict rate limiting.
    case critical
}
