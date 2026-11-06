// MARK: - NetworkKit/Middlewares/Cache/CacheMiddleware.swift
//
import Foundation
import WaanguCoreKit
/// Middleware de cache HTTP.
///
/// Pipeline :
/// - `prepare`           → applique la CachePolicy sur la URLRequest
/// - `process(response)` → stockage explicite pour cacheOnly, alwaysUseCache **et networkFirst**
/// - `process(error)`    → fallback cache sur erreur réseau (networkFirst uniquement)
///
/// Ordre d'injection contractuel dans APIClientFactory :
///   1. AuthMiddleware      — refresh 401
///   2. LoggingMiddleware   — debug logging
///   3. CacheMiddleware     — en dernier, après les middlewares de récupération
///
/// ⚠️ Utiliser URLSession(configuration: .ephemeral) pour éviter que URLCache système
///    n'interfère avec les politiques de stockage explicites de ce middleware.
final class CacheMiddleware: HTTPMiddlewareProtocol {

    // MARK: - Constants

    private static let defaultMaxAge: TimeInterval = 3600

    // MARK: - Dependencies

    private let cache: any CacheStoreProtocol
    private let logger: AppLogger

    // MARK: - Init

    init(
        cache: any CacheStoreProtocol = URLCache.shared,
        logger: AppLogger
    ) {
        self.cache = cache
        self.logger = logger
    }

    // MARK: - prepare ( CACHE AVANT RÉSEAU)

    func prepare(
        _ request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> URLRequest {

        var req = request

        let ttl = endpoint.cachePolicy.ttl > 0
            ? endpoint.cachePolicy.ttl
            : Self.defaultMaxAge

        switch endpoint.cachePolicy {

        case .alwaysUseCache, .cacheOnly:

            if let cached = cache.cachedResponse(for: request),
               let http = cached.response as? HTTPURLResponse {

                let age = cacheEntryAge(response: http)

                if !isCacheExpired(age: age, maxAge: ttl) {

                    await logger.log(
                        "📦 [\(endpointKey)] ✅ CACHE HIT (served before network) age=\(Int(age))s",
                        level: .info
                    )

                    // 🔥 STOP NETWORK
                    throw CacheHitError.hit(cached.data)

                } else {
                    await logger.log(
                        "📦 [\(endpointKey)] Cache expired age=\(Int(age))s > ttl=\(Int(ttl))s",
                        level: .debug
                    )
                }

            } else {
                await logger.log(
                    "📦 [\(endpointKey)] Cache MISS (prepare phase)",
                    level: .debug
                )
            }

            // fallback réseau
            req.cachePolicy = .reloadIgnoringLocalCacheData

        case .networkFirst:
            req.cachePolicy = .reloadIgnoringLocalCacheData

        case .noCache:
            req.cachePolicy = .reloadIgnoringLocalCacheData
        }

        return req
    }

    // MARK: - process(response:) (🔥 STORE CACHE)

    func process(
        response data: Data,
        for request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> Data {

        switch endpoint.cachePolicy {

        case .cacheOnly, .alwaysUseCache, .networkFirst:

            let maxAge = endpoint.cachePolicy.ttl > 0
                ? endpoint.cachePolicy.ttl
                : Self.defaultMaxAge

            let hadCache = cache.cachedResponse(for: request) != nil

            storeManually(data: data, for: request, maxAge: maxAge)

            await logger.log(
                "📦 [\(endpointKey)] Stored in cache (ttl=\(Int(maxAge))s)",
                level: .debug
            )

            if hadCache {
                await logger.log(
                    "📦 [\(endpointKey)] Cache updated (overwritten)",
                    level: .debug
                )
            }

        case .noCache:
            break
        }

        return data
    }

    // MARK: - process(error:) (FALLBACK CACHE)

    func process(
        error: APIError,
        for request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> Data? {

        guard
            case .networkFirst = endpoint.cachePolicy,
            error.isNetworkRelated,
            let cached = cache.cachedResponse(for: request),
            let http = cached.response as? HTTPURLResponse
        else { return nil }

        let ttl = endpoint.cachePolicy.ttl > 0
            ? endpoint.cachePolicy.ttl
            : Self.defaultMaxAge

        let age = cacheEntryAge(response: http)

        if isCacheExpired(age: age, maxAge: ttl) {
            await logger.log(
                "📦 [\(endpointKey)] Cache expired → fallback rejected",
                level: .debug
            )
            return nil
        }

        await logger.log(
            "📦 [\(endpointKey)] ⚠️ FALLBACK CACHE USED age=\(Int(age))s — \(error)",
            level: .warning
        )

        return cached.data
    }

    // MARK: - Invalidation

    func invalidate(for request: URLRequest) {
        cache.removeCachedResponse(for: request)
    }

    func invalidateAll() {
        cache.removeAllCachedResponses()
    }

    // MARK: - Storage

    private func storeManually(data: Data, for request: URLRequest, maxAge: TimeInterval) {

        guard let url = request.url else { return }

        let now = Date()
        let expiresDate = now.addingTimeInterval(maxAge)

        let headers: [String: String] = [
            "Content-Type": "application/json",
            "Cache-Control": "max-age=\(Int(maxAge))",
            "Expires": Self.httpDateFormatter.string(from: expiresDate),
            "Date": Self.httpDateFormatter.string(from: now)
        ]

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else { return }

        cache.storeCachedResponse(
            CachedURLResponse(response: response, data: data),
            for: request
        )
    }

    // MARK: - Cache Age

    private nonisolated func cacheEntryAge(response: HTTPURLResponse) -> TimeInterval {

        let headers = response.allHeaderFields

        if let ageStr = headers["Age"] as? String,
           let age = TimeInterval(ageStr) {
            return age
        }

        if let dateStr = headers["Date"] as? String {
            if let date = Self.httpDateFormatter.date(from: dateStr) {
                return Date().timeIntervalSince(date)
            }
            if let date = Self.iso8601Formatter.date(from: dateStr) {
                return Date().timeIntervalSince(date)
            }
        }

        return .infinity
    }

    private nonisolated func isCacheExpired(age: TimeInterval, maxAge: TimeInterval) -> Bool {
        age > maxAge
    }

    // MARK: - Formatters

    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        f.timeZone = TimeZone(abbreviation: "GMT")
        return f
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
