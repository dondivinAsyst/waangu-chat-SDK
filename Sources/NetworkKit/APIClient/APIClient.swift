// MARK: - NetworkKit/APIClient/APIClient.swift
//
// Améliorations vs version originale :
// 1. isConnected lit networkMonitor dynamiquement — plus de snapshot figé
// 2. getPerformanceMetrics() retourne APIPerformanceMetrics (CoreKit) via toPublic()
// 3. request(endpoint:) accepte any APIEndpoint — conforme à APIClientProtocol (CoreKit)
//    La surcharge avec EndpointPolicyProviding est la méthode interne principale
// 4. networkMonitor injecté dans l'acteur pour la lecture dynamique

import Foundation
import WaanguCoreKit

public actor APIClient: APIClientProtocol {

    // MARK: - Properties

    private let session: URLSession
    private let baseURL: String
    private var middlewares: [any HTTPMiddlewareProtocol]
    private let circuitBreaker: any CircuitBreakerService
    private let logger: AppLogger
    private let networkMonitor: any NetworkMonitoringProtocol
    private let performanceMonitor: any PerformanceMonitorProtocol
    private let policyResolver: any AdaptivePolicyResolvingProtocol
    private let rateLimiter: (any RateLimiterService)?
    private let dedupService: (any DedupService)?
    private let decoder: JSONDecoder
    private let metricsCollector = MetricsCollector()
    private var activeTasks: [String: Task<(Data, URLResponse), Error>] = [:]

    private var runTimeConfig: DeviceConfiguration
    private var configTimestamp: Date
    private static let configStalenessInterval: TimeInterval = 30

    private var eventObservationTask: Task<Void, Never>?

    // MARK: - Init

    private init(
        baseURL: String,
        session: URLSession,
        middlewares: [any HTTPMiddlewareProtocol],
        circuitBreaker: any CircuitBreakerService,
        rateLimiter: (any RateLimiterService)?,
        dedupService: (any DedupService)?,
        logger: AppLogger,
        runTimeConfig: DeviceConfiguration,
        networkMonitor: any NetworkMonitoringProtocol,
        performanceMonitor: any PerformanceMonitorProtocol,
        policyResolver: any AdaptivePolicyResolvingProtocol
    ) {
        self.baseURL = baseURL
        self.session = session
        self.middlewares = middlewares
        self.circuitBreaker = circuitBreaker
        self.rateLimiter = rateLimiter
        self.dedupService = dedupService
        self.logger = logger
        self.runTimeConfig = runTimeConfig
        self.networkMonitor = networkMonitor
        self.performanceMonitor = performanceMonitor
        self.policyResolver = policyResolver
        self.configTimestamp = Date()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Factory

    public static func makeConfigured(
        baseURL: String,
        session: URLSession = URLSession(configuration: .ephemeral),
        middlewares: [any HTTPMiddlewareProtocol] = [],
        circuitBreaker: any CircuitBreakerService,
        rateLimiter: (any RateLimiterService)? = nil,
        dedupService: (any DedupService)? = nil,
        logger: AppLogger,
        runTimeConfig: DeviceConfiguration,
        networkMonitor: any NetworkMonitoringProtocol,
        performanceMonitor: any PerformanceMonitorProtocol,
        policyResolver: any AdaptivePolicyResolvingProtocol
    ) async -> APIClient {

        var finalMiddlewares = middlewares

        if !middlewares.contains(where: { $0 is any RetryCapable }) {
            let retry = buildRetryMiddleware(runTimeConfig: runTimeConfig, logger: logger)
            finalMiddlewares.append(retry)
        }

        let client = APIClient(
            baseURL: baseURL,
            session: session,
            middlewares: finalMiddlewares,
            circuitBreaker: circuitBreaker,
            rateLimiter: rateLimiter,
            dedupService: dedupService,
            logger: logger,
            runTimeConfig: runTimeConfig,
            networkMonitor: networkMonitor,
            performanceMonitor: performanceMonitor,
            policyResolver: policyResolver
        )

        await client.startObservingCriticalEvents()

        await logger.log("APIClient initialized — baseURL: \(baseURL)", level: .info)
        return client
    }

    private static func buildRetryMiddleware(
        runTimeConfig: DeviceConfiguration,
        logger: AppLogger
    ) -> RetryMiddleware {
        let policy: HTTPRetryPolicy
        switch runTimeConfig.retryProfile {
        case .none:         policy = HTTPRetryPolicy(strategy: .none, retryableStatusCodes: [], retryableURLErrorCodes: [])
        case .conservative: policy = .production
        case .standard:     policy = .default
        case .aggressive:   policy = .staging
        }
        return RetryMiddleware(policy: policy, logger: logger)
    }

    // MARK: - Adaptive config refresh

    private func refreshConfigIfStale() async {
        guard Date().timeIntervalSince(configTimestamp) > Self.configStalenessInterval else { return }
        await refreshConfig(reason: "stale")
    }

    private func refreshConfig(reason: String) async {
        let newConfig = await policyResolver.resolve(
            performanceMonitor: performanceMonitor,
            networkMonitor: networkMonitor
        )

        let changed = newConfig.maxConcurrentRequests != runTimeConfig.maxConcurrentRequests
            || newConfig.retryProfile != runTimeConfig.retryProfile
            || newConfig.timeoutMultiplier != runTimeConfig.timeoutMultiplier

        runTimeConfig = newConfig
        configTimestamp = Date()

        if changed {
            rebuildRetryMiddleware()
            await logger.log(
                "RuntimeConfig refreshed (\(reason)): concurrent=\(newConfig.maxConcurrentRequests), "
                + "retry=\(newConfig.retryProfile), timeout×\(String(format: "%.1f", newConfig.timeoutMultiplier))",
                level: .info
            )
        }
    }

    private func rebuildRetryMiddleware() {
        middlewares.removeAll { $0 is any RetryCapable }
        let retry = Self.buildRetryMiddleware(runTimeConfig: runTimeConfig, logger: logger)
        middlewares.append(retry)
    }

    private func startObservingCriticalEvents() {
        eventObservationTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.performanceMonitor.criticalEvents()
            for await _ in stream {
                guard !Task.isCancelled else { break }
                await self.refreshConfig(reason: "critical-event")
            }
        }
    }

    // MARK: - APIClientProtocol

    public var isConnected: Bool {
        get async { await networkMonitor.isConnected }
    }

    public func request<T: Decodable>(endpoint: any APIEndpoint) async throws -> T {
        guard let policyEndpoint = endpoint as? (any APIEndpoint & EndpointPolicyProviding) else {
            throw APIError.custom("Endpoint must conform to EndpointPolicyProviding")
        }
        return try await requestWithPolicy(endpoint: policyEndpoint)
    }

    func requestWithPolicy<T: Decodable>(
        endpoint: any APIEndpoint & EndpointPolicyProviding
    ) async throws -> T {
        let endpointKey = self.endpointKey(for: endpoint)
        let traceId = UUID().uuidString

        await metricsCollector.recordRequestStart()
        await logger.log(
            "[\(traceId)] Starting: \(endpoint.path) [Priority: \(endpoint.priority)]",
            level: .info
        )

        do {
            let result: T = try await executeRequest(
                endpoint: endpoint,
                endpointKey: endpointKey,
                traceId: traceId
            )
            await metricsCollector.recordRequestEnd()
            return result
        } catch {
            await metricsCollector.recordRequestEnd()
            throw error
        }
    }

    public func cancelAllRequests() async {
        await logger.log("Cancelling all active requests (\(activeTasks.count))", level: .info)
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        tasks.forEach { $0.cancel() }
        await withTaskGroup(of: Void.self) { group in
            for task in tasks { group.addTask { _ = try? await task.value } }
        }
    }

    public func cancelRequest(for endpoint: any APIEndpoint) async {
        let prefix = endpointKey(for: endpoint)
        let keysToCancel = activeTasks.keys.filter { $0.hasPrefix(prefix) }
        keysToCancel.forEach { activeTasks[$0]?.cancel(); activeTasks[$0] = nil }
        await logger.log("Cancelled: \(prefix)", level: .info)
    }

    public func getPerformanceMetrics() async -> APIPerformanceMetrics {
        await metricsCollector.snapshot().toPublic()
    }

    public func getCircuitBreaker() -> any CircuitBreakerService {
        circuitBreaker
    }

    // MARK: - Execute Request

    private func executeRequest<T: Decodable>(
        endpoint: any APIEndpoint & EndpointPolicyProviding,
        endpointKey: String,
        traceId: String
    ) async throws -> T {

        // 0. Re-evaluate config if stale or conditions changed
        await refreshConfigIfStale()

        // 1. Connectivity
        guard await networkMonitor.isConnected else {
            await logger.log("[\(traceId)] No internet connection", level: .error)
            throw APIError.noInternetConnection
        }

        // 2. Rate limiting
        if let rateLimiter,
           !(await rateLimiter.shouldAllowRequest(endpointKey: endpointKey, policy: endpoint.rateLimitPolicy)) {
            await metricsCollector.recordRateLimited()
            throw APIError.rateLimited(endpointKey: endpointKey)
        }

        // 3. Circuit breaker
        await circuitBreaker.setProfile(endpoint.circuitBreakerProfile, forEndpoint: endpointKey)
        guard await circuitBreaker.shouldAllowRequest(
            endpointKey: endpointKey,
            profile: endpoint.circuitBreakerProfile
        ) else {
            await metricsCollector.recordCircuitBreakerBlock()
            throw APIError.circuitBreakerOpen(endpointKey: endpointKey)
        }

        // 4. Retry loop
        guard let retryMiddleware = middlewares.compactMap({ $0 as? any RetryCapable }).first else {
            return try await executeWithDedup(
                endpointKey: endpointKey,
                isDeduplicable: endpoint.method == .get
            ) {
                try await self.performActualRequest(endpoint: endpoint, endpointKey: endpointKey, traceId: traceId, attempt: 0)
            }
        }

        var attempt = 0
        let maxRetries = await retryMiddleware.maxRetries
        var circuitBreakerFailureRecorded = false
        var tokenRefreshAttempted = false

        while attempt <= maxRetries {
            do {
                let dedupKey = attempt == 0 ? endpointKey : "\(endpointKey)#\(attempt)"
                let result: T = try await executeWithDedup(
                    endpointKey: dedupKey,
                    isDeduplicable: endpoint.method == .get
                ) {
                    try await self.performActualRequest(
                        endpoint: endpoint,
                        endpointKey: endpointKey,
                        traceId: traceId,
                        attempt: attempt
                    )
                }
                return result

            } catch {
                let apiError = error as? APIError ?? mapURLSessionError(error)

                // 401 — refresh token once
                if apiError.isUnauthorized && !tokenRefreshAttempted {
                    tokenRefreshAttempted = true
                    try await refreshTokenWithTimeout(
                        error: apiError,
                        endpoint: endpoint,
                        endpointKey: endpointKey,
                        traceId: traceId
                    )
                    continue
                }

                // Error recovery via middlewares
                let errorRequest = try await buildRequest(for: endpoint, traceId: traceId)
                if let recovered = try await processError(apiError, for: errorRequest, endpoint: endpoint, endpointKey: endpointKey) {
                    return try decodeResponse(recovered, as: T.self)
                }

                // Retry decision
                if attempt < maxRetries,
                   await retryMiddleware.shouldRetry(
                       error: apiError,
                       attempt: attempt,
                       isIdempotent: endpoint.isIdempotent
                   ) {
                    attempt += 1

                    if apiError.shouldTriggerCircuitBreaker && !circuitBreakerFailureRecorded {
                        await circuitBreaker.recordFailure(endpointKey: endpointKey, profile: endpoint.circuitBreakerProfile)
                        circuitBreakerFailureRecorded = true
                    }

                    let delay = await retryMiddleware.retryDelay(for: attempt - 1)
                    let jittered = delay * Double.random(in: 0.8...1.2)

                    await retryMiddleware.logRetry(endpointKey: endpointKey, attempt: attempt - 1, delay: jittered, error: apiError)
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: UInt64(jittered * 1_000_000_000))
                    continue
                }

                // Final failure
                if apiError.shouldTriggerCircuitBreaker && !circuitBreakerFailureRecorded {
                    await circuitBreaker.recordFailure(endpointKey: endpointKey, profile: endpoint.circuitBreakerProfile)
                }

                let errorType = String(describing: type(of: apiError))
                let isTimeout: Bool = { if case .timeout = apiError { return true }; return false }()
                await metricsCollector.recordFailure(errorType: errorType, isTimeout: isTimeout)
                await logger.log("[\(traceId)] Failed after \(attempt) attempt(s): \(apiError)", level: .error)
                throw apiError
            }
        }

        throw APIError.unknown("Unexpected exit from retry loop")
    }

    // MARK: - Auth Refresh

    private func refreshTokenWithTimeout(
        error: APIError,
        endpoint: any APIEndpoint & EndpointPolicyProviding,
        endpointKey: String,
        traceId: String
    ) async throws {
        let timeoutNs = UInt64(runTimeConfig.minTimeout * 1_000_000_000)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let req = try await self.buildRequest(for: endpoint, traceId: traceId)
                _ = try await self.processError(error, for: req, endpoint: endpoint, endpointKey: endpointKey)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNs)
                await self.logger.log("[\(traceId)] ⏱ Auth refresh timed out", level: .error)
                throw APIError.timeout
            }
            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Middleware Pipeline

    /// Passes the error through all middlewares, forwarding the typed endpoint directly.
    private func processError(
        _ error: APIError,
        for request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> Data? {
        for middleware in middlewares {
            if let recovered = try await middleware.process(
                error: error,
                for: request,
                endpoint: endpoint,
                endpointKey: endpointKey
            ) {
                return recovered
            }
        }
        return nil
    }

    /// - Parameter isDeduplicable: whether concurrent callers may legitimately be
    ///   handed one shared response.
    ///
    ///   Only true for GETs. `endpointKey` is method + path for everything else —
    ///   the body is deliberately excluded — so two different POSTs to the same
    ///   path look identical here and get coalesced into one request whose single
    ///   response is returned to both callers.
    ///
    ///   That is wrong for any request that *creates* something. Sending several
    ///   photos at once fired concurrent `multipart/initiate-with-presigned` calls,
    ///   which collapsed into one: every photo received the same `uploadId` and
    ///   `key`, uploaded its parts over the others, and then only the first
    ///   `complete` could succeed — the rest got "the specified multipart upload
    ///   does not exist". Sending them one at a time always worked, because nothing
    ///   overlapped.
    private func executeWithDedup<T>(
        endpointKey: String,
        isDeduplicable: Bool,
        performRequest: @escaping () async throws -> T
    ) async throws -> T {
        guard isDeduplicable, let dedupService else {
            return try await performRequest()
        }
        return try await dedupService.execute(endpointKey: endpointKey) { try await performRequest() }
    }

    // MARK: - Single Request

    private func performActualRequest<T: Decodable>(
        endpoint: any APIEndpoint & EndpointPolicyProviding,
        endpointKey: String,
        traceId: String,
        attempt: Int
    ) async throws -> T {

        let startTime = Date()
        let request: URLRequest

        do {
            var builtRequest = try await buildRequest(for: endpoint, traceId: traceId)

            //  prepare (peut throw CacheHitError)
            for middleware in middlewares {
                builtRequest = try await middleware.prepare(
                    builtRequest,
                    endpoint: endpoint,
                    endpointKey: endpointKey
                )
            }

            request = builtRequest

        } catch let cacheError as CacheHitError {

            await logger.log(
                "[\(traceId)] ⚡️ Served from CACHE (no network call)",
                level: .info
            )

            let decoded: T = try decodeResponse(cacheError.hitData, as: T.self)

            let duration = Date().timeIntervalSince(startTime)
            await metricsCollector.recordSuccess(duration: duration)

            return decoded
        }

        // 🔽 Ton code existant reste inchangé à partir d’ici

        if let body = request.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            await logger.log(
                "[\(traceId)] → \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "") [Attempt: \(attempt + 1)]\nBody: \(bodyString)",
                level: .debug
            )
        }

        let taskKey = "\(endpointKey):\(traceId)"
        let dataTask = Task<(Data, URLResponse), Error> {
            try await self.session.data(for: request)
        }

        activeTasks[taskKey] = dataTask
        defer { activeTasks[taskKey] = nil }

        let (data, response) = try await dataTask.value

        try await validateResponse(
            response, data: data, for: request, traceId: traceId,
            deliversBusinessErrors: endpoint is any BusinessErrorEnvelopeEndpoint
        )

        var processedData = data
        for middleware in middlewares.reversed() {
            processedData = try await middleware.process(
                response: processedData,
                for: request,
                endpoint: endpoint,
                endpointKey: endpointKey
            )
        }

        let decoded: T = try decodeResponse(processedData, as: T.self)
        let duration = Date().timeIntervalSince(startTime)

        await metricsCollector.recordSuccess(duration: duration)
        await circuitBreaker.recordSuccess(endpointKey: endpointKey, profile: endpoint.circuitBreakerProfile)

        await logger.log(
            "[\(traceId)] ✅ \(endpointKey) in \(String(format: "%.2f", duration))s [Attempt: \(attempt + 1)]",
            level: .info
        )

        return decoded
    }

    // MARK: - Helpers

    private nonisolated func endpointKey(for endpoint: any APIEndpoint) -> String {
        guard endpoint.method == .get, let params = endpoint.parameters, !params.isEmpty else {
            return "\(endpoint.method.rawValue):\(endpoint.path)"
        }
        let query = params
            .sorted { $0.key < $1.key }
            .reduce(into: "") { result, pair in
                if !result.isEmpty { result += "&" }
                let k = pair.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pair.key
                let v = "\(pair.value)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "\(pair.value)"
                result += "\(k)=\(v)"
            }
        return "\(endpoint.method.rawValue):\(endpoint.path)|\(query)"
    }

    /// Si `path` est une URL absolue (`http…` / `https…`), elle est utilisée telle quelle (ex. fetch serveur-driven).
    private func resolvedURLString(for endpoint: any APIEndpoint) -> String {
        let path = endpoint.path
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        return baseURL + path
    }

    private func buildRequest(
        for endpoint: any APIEndpoint & EndpointPolicyProviding,
        traceId: String?
    ) async throws -> URLRequest {
        let urlString = resolvedURLString(for: endpoint)
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue

//        request.setValue("1.3.9", forHTTPHeaderField: "Version")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
//        request.setValue("iOS-\(Bundle.main.versionNumber)", forHTTPHeaderField: "User-Agent")

        endpoint.headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        if let traceId {
//            request.setValue(traceId, forHTTPHeaderField: "X-Request-ID")
//            request.setValue(traceId, forHTTPHeaderField: "X-Trace-ID")
        }

        if let parameters = endpoint.parameters, !parameters.isEmpty {
            switch endpoint.method {
            case .get:
                var components = URLComponents(string: urlString)
                components?.queryItems = parameters.sorted(by: { $0.key < $1.key }).map {
                    URLQueryItem(name: $0.key, value: "\($0.value)")
                }
                if let fullURL = components?.url {
                    request.url = fullURL
                }
            case .post, .put, .patch, .delete:
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
            }
        }

        let baseTimeout = endpoint.timeoutPolicy.baseTimeout
        let adjusted = baseTimeout * runTimeConfig.timeoutMultiplier
        request.timeoutInterval = min(max(adjusted, runTimeConfig.minTimeout), runTimeConfig.maxTimeout)

        return request
    }

    private func validateResponse(
        _ response: URLResponse,
        data: Data,
        for request: URLRequest,
        traceId: String,
        deliversBusinessErrors: Bool = false
    ) async throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // L'en-tête `Date` donne l'heure du serveur — voir `ServerClock`.
        ServerClock.shared.observe(response: http)

        // Voir `BusinessErrorEnvelopeEndpoint` : le code métier ne se perd pas.
        if deliversBusinessErrors,
           BusinessErrorEnvelope.delivers(statusCode: http.statusCode, body: data) {
            return
        }

        // ✅ Enhanced logging with full URL and actual status code
        let fullURL = request.url?.absoluteString ?? "unknown"
        let method = request.httpMethod ?? "?"
        await logger.log("[\(traceId)] validateResponse(_:data:for:traceId:) - [\(traceId)] HTTP \(http.statusCode) for \(method) \(fullURL)", level: .debug)
        
        // ✅ Log response body if not 2xx to see what server actually returned
        if http.statusCode < 200 || http.statusCode >= 300 {
            if let responseBody = String(data: data, encoding: .utf8) {
                await logger.log("[\(traceId)] Response body: \(responseBody)", level: .debug)
            }
        }

        switch http.statusCode {
        case 200...299, 304: return
        case 400:   throw APIError.clientError(statusCode: 400, message: extractErrorMessage(from: data))
        case 401:   throw APIError.unauthorized
        case 403:   throw APIError.forbidden
        case 404:   throw APIError.notFound
        case 409:   throw APIError.clientError(statusCode: 409, message: extractErrorMessage(from: data))
        case 429:   throw APIError.rateLimited(endpointKey: request.url?.path ?? "unknown")
        case 400...499: throw APIError.clientError(statusCode: http.statusCode, message: extractErrorMessage(from: data))
        case 500...599: throw APIError.serverError(statusCode: http.statusCode)
        default:    throw APIError.unknown("HTTP \(http.statusCode)")
        }
    }

    private struct APIErrorBody: Decodable {
        let message: String?
        let error: String?
        let detail: String?
        let errors: [String]?

        var bestMessage: String {
            [message, error, detail, errors?.first]
                .compactMap { $0 }
                .first(where: { !$0.isEmpty }) ?? ""
        }
    }

    private nonisolated func extractErrorMessage(from data: Data) -> String {
        (try? decoder.decode(APIErrorBody.self, from: data))?.bestMessage ?? ""
    }

    private func decodeResponse<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        try decoder.decode(T.self, from: data)
    }

    private nonisolated func mapURLSessionError(_ error: Error) -> APIError {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorTimedOut:                return .timeout
        case NSURLErrorNotConnectedToInternet:  return .noInternetConnection
        case NSURLErrorCancelled:               return .cancelled
        case NSURLErrorNetworkConnectionLost:   return .networkConnectionLost
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateNotYetValid:
            return .sslError(error)
        default: return .networkError(error)
        }
    }
}
