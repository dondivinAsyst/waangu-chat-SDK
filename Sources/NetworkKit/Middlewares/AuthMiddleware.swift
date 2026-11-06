// MARK: - NetworkKit/Middlewares/AuthMiddleware.swift

import Foundation
import WaanguCoreKit
/// Middleware d'authentification.
///
/// Responsabilités :
/// - Injecte le token Bearer sur toutes les requêtes authentifiées
/// - Injecte les headers de localisation (Accept-Language, zone)
/// - Skip l'auth sur les endpoints publics (login, checkPhone...)
/// - `process(error:)` retourne nil — le refresh 401 est géré directement
///   dans la retry loop d'APIClient via `refreshTokenWithTimeout`
final class AuthMiddleware: HTTPMiddlewareProtocol {
    

    private let tokenManager: any TokenManagerProtocol
    private let logger: AppLogger
    private let languageCode: String
    private let zone: String
    private let basicAuthToken: String?

    init(
        tokenManager: any TokenManagerProtocol,
        logger: AppLogger,
        basicAuthToken: String? = nil,
        languageCode: String = Locale.current.identifier,
        zone: String = "burundi"
    ) {
        self.tokenManager = tokenManager
        self.logger = logger
        self.basicAuthToken = basicAuthToken
        self.languageCode = languageCode
        self.zone = zone
    }

    // MARK: - Language

    /// `en`, unless the endpoint declares its own `Accept-Language` — then `nil`,
    /// and the endpoint's value is left on the request.
    static func defaultLanguage(for endpoint: any EndpointPolicyProviding) -> String? {
        (endpoint as? any APIEndpoint)?.headers?["Accept-Language"] == nil ? "en" : nil
    }

    // MARK: - prepare

    func prepare(
        _ request: URLRequest,
        endpoint: any EndpointPolicyProviding,
        endpointKey: String
    ) async throws -> URLRequest {
        var req = request

        // `en` by default: some Wallet APIs behave strangely with another value.
        // An endpoint that declares its own language keeps it — Chat Core writes
        // user-facing messages in that language. The client has already copied
        // the endpoint's headers onto the request, so overwriting here would
        // silently send `en` for every call.
        if let language = Self.defaultLanguage(for: endpoint) {
            req.setValue(language, forHTTPHeaderField: "Accept-Language")
        }
        
        req.setValue(zone, forHTTPHeaderField: "zone")
        if let basicAuthToken {
            req.setValue(basicAuthToken, forHTTPHeaderField: "Authorization")
        }

        guard !shouldSkipAuth(for: request) else {
            await logger.log("Auth skipped for: \(endpointKey)", level: .debug)
            return req
        }

        if let token = try await tokenManager.getAccessToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            await logger.log("Auth token injected for: \(endpointKey)", level: .debug)
        } else {
            await logger.log("No auth token available for: \(endpointKey)", level: .warning)
        }
//        A implementer selon le cahier de charge
        
//        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
//        req.setValue(context.tenantId, forHTTPHeaderField: "X-Tenant-Id")
//        req.setValue(context.organizationId ?? "", forHTTPHeaderField: "X-Organization-Id")
//        req.setValue(context.countryCode, forHTTPHeaderField: "X-Country-Code")
//        req.setValue(context.locale, forHTTPHeaderField: "Accept-Language")
//        req.setValue(context.currency, forHTTPHeaderField: "X-Currency-Code")
//        req.setValue(context.sessionId, forHTTPHeaderField: "X-Session-Id")
//        req.setValue(context.deviceId, forHTTPHeaderField: "X-Device-Id")
//        req.setValue(context.appVersion, forHTTPHeaderField: "X-App-Version")
//        req.setValue(correlationId, forHTTPHeaderField: "X-Correlation-Id")
//        req.setValue(endpoint.criticality.rawValue, forHTTPHeaderField: "X-Endpoint-Criticality")
//        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        X-Request-Signature
        return req
    }

    // MARK: - process(error:) — pass-through
    // 401 refresh is handled in APIClient.refreshTokenWithTimeout()
    // to benefit from the configurable timeout and retry loop.

    // MARK: - Private

    private func shouldSkipAuth(for request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        let skipPaths = [
            "/api/v2/user/sendDeviceInfo",
            "/api/user/checkPhone",
            "/api/user/login",
            "/api/user/verifyOTP",
            "/api/user/resendOTP",
            "api/homeIcon/getVersion"
        ]
        return skipPaths.contains { url.path.contains($0) }
    }
}
