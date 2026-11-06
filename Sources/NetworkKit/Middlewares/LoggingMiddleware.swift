// MARK: - NetworkKit/Middlewares/LoggingMiddleware.swift

import Foundation
import WaanguCoreKit
/// Middleware de logging du contenu des requêtes et réponses.
///
/// Séparation des responsabilités :
/// - `APIClient` logue le cycle de vie (start, retry, success, failure)
/// - `LoggingMiddleware` logue le contenu (headers, body)
///
/// Actif uniquement en DEBUG pour éviter de leaker des données sensibles en production.
final class LoggingMiddleware: HTTPMiddlewareProtocol {

    private let logger: AppLogger
    private static let maxBodyBytes = 2048
    private static let sensitiveHeaders: Set<String> = [
        "Authorization", "X-API-Key", "Cookie", "Set-Cookie"
    ]

    init(logger: AppLogger) {
        self.logger = logger
    }

    // MARK: - prepare

    func prepare(
        _ request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> URLRequest {
        #if DEBUG
        let traceId = request.value(forHTTPHeaderField: "X-Request-ID") ?? "?"

        await logger.log(
            "[\(traceId)] REQUEST: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")",
            level: .debug
        )

        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            let sanitized = headers.mapValues { value -> String in
                let key = headers.first(where: { $0.value == value })?.key ?? ""
                return Self.sensitiveHeaders.contains(key) ? "<redacted>" : value
            }
            await logger.log("[\(traceId)] ↑ headers: \(sanitized)", level: .debug)
        }

        if let body = request.httpBody, !body.isEmpty {
            await logger.log("[\(traceId)] ↑ body: \(bodyPreview(body))", level: .debug)
        }
        #endif
        return request
    }

    // MARK: - process(response:)

    func process(
        response data: Data,
        for request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> Data {
        #if DEBUG
        let traceId = request.value(forHTTPHeaderField: "X-Request-ID") ?? "?"
        if !data.isEmpty {
            await logger.log("[\(traceId)] ↓ body: \(bodyPreview(data))", level: .debug)
        }
        #endif
        return data
    }

    // MARK: - Private

    private func bodyPreview(_ data: Data) -> String {
        let max = Self.maxBodyBytes
        if let text = String(bytes: data.prefix(max), encoding: .utf8) {
            return data.count > max ? "\(text)… (\(data.count - max) bytes truncated)" : text
        }
        return "<binary data: \(data.count) bytes>"
    }
}
