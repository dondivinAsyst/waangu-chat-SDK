// MARK: - NetworkKit/Middlewares/RetryMiddleware.swift
//
// Amélioration vs version originale :
// retryDelay(for:) et logRetry() sont maintenant async — alignés avec RetryCapable.
// L'implémentation ne fait rien d'async mais la signature permet
// une implémentation future qui consulterait un service externe.

import Foundation
import WaanguCoreKit

final class RetryMiddleware: HTTPMiddlewareProtocol, RetryCapable {

    private let policy: HTTPRetryPolicy
    private let logger: AppLogger

    // MARK: - RetryCapable

    var maxRetries: Int {
        get async { policy.strategy.maxRetries }
    }

    init(policy: HTTPRetryPolicy = .default, logger: AppLogger) {
        self.policy = policy
        self.logger = logger
    }

    // MARK: - HTTPMiddlewareProtocol (pass-through)

    func prepare(_ request: URLRequest, endpointKey: String) async throws -> URLRequest {
        request
    }

    func process(response data: Data, for request: URLRequest, endpointKey: String) async throws -> Data {
        data
    }

    // MARK: - RetryCapable

    func shouldRetry(error: APIError, attempt: Int, isIdempotent: Bool) async -> Bool {
        guard attempt < policy.strategy.maxRetries else {
            await logger.log(
                "🔁 Retry limit reached (\(attempt)/\(policy.strategy.maxRetries))",
                level: .debug
            )
            return false
        }

        // `isIdempotent` was declared on every endpoint and read by nobody: the
        // decision below is made on the status code alone, so a POST that the
        // server had already acted on was repeated exactly like a GET.
        //
        // The case that exposed it was S3's multipart `complete`, which consumes
        // its upload id. The first call completed the upload, something downstream
        // returned 500, and the two retries could then only ever fail with "the
        // specified multipart upload does not exist" — turning one recoverable
        // failure into a certain one, and hiding the original error behind it.
        if !isIdempotent, !Self.provablyNeverReachedServer(error) {
            await logger.log(
                "🔁 Not retrying a non-idempotent request after \(error)",
                level: .debug
            )
            return false
        }

        switch error {
        case .serverError(let statusCode):
            return policy.retryableStatusCodes.contains(statusCode)
        case .clientError(let statusCode, _):
            return policy.retryableStatusCodes.contains(statusCode)
        case .networkError(let underlying):
            let urlError = underlying as? URLError ?? URLError(.unknown)
            return policy.retryableURLErrorCodes.contains(urlError.code)
        case .timeout:
            return policy.retryableURLErrorCodes.contains(.timedOut)
        case .networkConnectionLost:
            return policy.retryableURLErrorCodes.contains(.networkConnectionLost)
        default:
            return false
        }
    }

    /// Whether the request certainly never got as far as being processed.
    ///
    /// Deliberately narrow. A 5xx means the server ran something; a timeout or a
    /// dropped connection means we simply stopped listening — the work may well
    /// have completed. Only a connection that was never established lets us repeat
    /// a non-idempotent request without risking doing it twice.
    private static func provablyNeverReachedServer(_ error: APIError) -> Bool {
        guard case .networkError(let underlying) = error,
              let code = (underlying as? URLError)?.code else { return false }
        return code == .notConnectedToInternet || code == .cannotConnectToHost
    }

    func retryDelay(for attempt: Int) async -> TimeInterval {
        policy.strategy.delay(for: attempt)
    }

    func logRetry(
        endpointKey: String,
        attempt: Int,
        delay: TimeInterval,
        error: APIError
    ) async {
        await logger.log(
            "🔁 Retry #\(attempt + 1) for \(endpointKey) in \(String(format: "%.2f", delay))s — \(error)",
            level: .warning
        )
    }
}
