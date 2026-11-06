import Foundation
import Testing
import WaanguCoreKit
@testable import WaanguNetworkKit

/// Retrying a request the server may already have acted on can turn one
/// recoverable failure into a permanent one.
///
/// The case that prompted this: S3's multipart `complete` consumes its upload id.
/// The first call completed the upload, something downstream answered 500, and the
/// two retries could then only fail with "the specified multipart upload does not
/// exist" — the caller saw that, not the original error.
///
/// `isIdempotent` was declared on every endpoint and consulted by nothing; the
/// retry decision was made on the status code alone.
@Suite("Retry idempotency")
struct RetryIdempotencyTests {

    private func middleware() -> RetryMiddleware {
        RetryMiddleware(policy: .default, logger: .shared)
    }

    @Test("An idempotent request still retries a server error")
    func idempotentRetriesServerError() async {
        let retries = await middleware().shouldRetry(
            error: .serverError(statusCode: 500),
            attempt: 0,
            isIdempotent: true
        )
        #expect(retries)
    }

    @Test("A non-idempotent request does not retry a server error")
    func nonIdempotentDoesNotRetryServerError() async {
        let retries = await middleware().shouldRetry(
            error: .serverError(statusCode: 500),
            attempt: 0,
            isIdempotent: false
        )
        #expect(!retries)
    }

    /// A timeout is the dangerous one: we stopped listening, but the server may
    /// well have finished the work.
    @Test("A non-idempotent request does not retry a timeout")
    func nonIdempotentDoesNotRetryTimeout() async {
        let retries = await middleware().shouldRetry(
            error: .timeout,
            attempt: 0,
            isIdempotent: false
        )
        #expect(!retries)
    }

    /// A connection that was never established cannot have been acted on, so even
    /// a non-idempotent request may be repeated — this is what keeps a media send
    /// working across a flaky connection.
    ///
    /// `.notConnectedToInternet` rather than `.cannotConnectToHost`: the gate lets
    /// both through, but only the first is in the policy's retryable set, and the
    /// policy still has the last word.
    @Test("A non-idempotent request still retries when it never reached the server")
    func nonIdempotentRetriesWhenNeverConnected() async {
        let retries = await middleware().shouldRetry(
            error: .networkError(URLError(.notConnectedToInternet)),
            attempt: 0,
            isIdempotent: false
        )
        #expect(retries)
    }

    @Test("The attempt cap still applies")
    func attemptCapStillApplies() async {
        let retries = await middleware().shouldRetry(
            error: .serverError(statusCode: 500),
            attempt: 99,
            isIdempotent: true
        )
        #expect(!retries)
    }
}
