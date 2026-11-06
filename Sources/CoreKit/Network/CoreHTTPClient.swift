////
////  CoreHTTPClient.swift
////  CoreKit
////
////  Centralized HTTP client with BFF-only enforcement
////  RULE: CoreHTTPClient BFF-only créé
////
//
//import Foundation
//import SecurityKit
//
///// Centralized HTTP client
///// All HTTP requests must go through this client with BFF-only enforcement
//public actor CoreHTTPClient {
//    
//    public static let shared = CoreHTTPClient()
//    
//    private let session: URLSession
//    private let allowedHostsPolicy: AllowedHostsPolicy
//    private let traceContextValidator: TraceContextValidator
//    private var bffBaseURL: String?
//    
//    private init() {
//        let configuration = URLSessionConfiguration.default
//        configuration.timeoutIntervalForRequest = 30
//        configuration.timeoutIntervalForResource = 300
//        configuration.waitsForConnectivity = true
//        
//        self.session = URLSession(configuration: configuration)
//        self.allowedHostsPolicy = AllowedHostsPolicy.shared
//        self.traceContextValidator = TraceContextValidator.shared
//    }
//    
//    // MARK: - Configuration
//    
//    /// Configure BFF base URL (must be called on app launch)
//    public func configureBFF(baseURL: String, allowedHosts: [String]) async throws {
//        // Validate BFF URL
//        guard let url = URL(string: baseURL), url.host != nil else {
//            throw HTTPClientError.invalidBFFURL(url: baseURL)
//        }
//        
//        // Set allowed hosts
//        await allowedHostsPolicy.setAllowedHosts(allowedHosts)
//        
//        // Validate BFF host is in allowed list
//        try await allowedHostsPolicy.validateURL(baseURL)
//        
//        self.bffBaseURL = baseURL
//    }
//    
//    // MARK: - Request Methods
//    
//    /// Perform GET request
//    public func get<T: Decodable>(
//        path: String,
//        queryParameters: [String: String]? = nil,
//        headers: [String: String]? = nil,
//        correlationId: CorrelationId? = nil,
//        traceId: String? = nil
//    ) async throws -> T {
//        let request = try await buildRequest(
//            path: path,
//            method: "GET",
//            queryParameters: queryParameters,
//            body: nil as Data?,
//            headers: headers,
//            correlationId: correlationId,
//            traceId: traceId
//        )
//        
//        return try await execute(request: request)
//    }
//    
//    /// Perform POST request
//    public func post<T: Decodable, B: Encodable>(
//        path: String,
//        body: B,
//        headers: [String: String]? = nil,
//        correlationId: CorrelationId? = nil,
//        idempotencyKey: String? = nil,
//        traceId: String? = nil
//    ) async throws -> T {
//        let bodyData = try JSONEncoder().encode(body)
//        
//        var requestHeaders = headers ?? [:]
//        if let idempotencyKey = idempotencyKey {
//            requestHeaders["X-Idempotency-Key"] = idempotencyKey
//        }
//        
//        let request = try await buildRequest(
//            path: path,
//            method: "POST",
//            queryParameters: nil,
//            body: bodyData,
//            headers: requestHeaders,
//            correlationId: correlationId,
//            traceId: traceId
//        )
//        
//        return try await execute(request: request)
//    }
//    
//    /// Perform PUT request
//    public func put<T: Decodable, B: Encodable>(
//        path: String,
//        body: B,
//        headers: [String: String]? = nil,
//        correlationId: CorrelationId? = nil,
//        idempotencyKey: String? = nil,
//        traceId: String? = nil
//    ) async throws -> T {
//        let bodyData = try JSONEncoder().encode(body)
//        
//        var requestHeaders = headers ?? [:]
//        if let idempotencyKey = idempotencyKey {
//            requestHeaders["X-Idempotency-Key"] = idempotencyKey
//        }
//        
//        let request = try await buildRequest(
//            path: path,
//            method: "PUT",
//            queryParameters: nil,
//            body: bodyData,
//            headers: requestHeaders,
//            correlationId: correlationId,
//            traceId: traceId
//        )
//        
//        return try await execute(request: request)
//    }
//    
//    /// Perform DELETE request
//    public func delete<T: Decodable>(
//        path: String,
//        headers: [String: String]? = nil,
//        correlationId: CorrelationId? = nil,
//        traceId: String? = nil
//    ) async throws -> T {
//        let request = try await buildRequest(
//            path: path,
//            method: "DELETE",
//            queryParameters: nil,
//            body: nil as Data?,
//            headers: headers,
//            correlationId: correlationId,
//            traceId: traceId
//        )
//        
//        return try await execute(request: request)
//    }
//    
//    /// Perform PATCH request
//    public func patch<T: Decodable, B: Encodable>(
//        path: String,
//        body: B,
//        headers: [String: String]? = nil,
//        correlationId: CorrelationId? = nil,
//        traceId: String? = nil
//    ) async throws -> T {
//        let bodyData = try JSONEncoder().encode(body)
//        
//        let request = try await buildRequest(
//            path: path,
//            method: "PATCH",
//            queryParameters: nil,
//            body: bodyData,
//            headers: headers,
//            correlationId: correlationId,
//            traceId: traceId
//        )
//        
//        return try await execute(request: request)
//    }
//    
//    // MARK: - Request Building
//    
//    private func buildRequest<B>(
//        path: String,
//        method: String,
//        queryParameters: [String: String]?,
//        body: B?,
//        headers: [String: String]?,
//        correlationId: CorrelationId?,
//        traceId: String?
//    ) async throws -> URLRequest where B: Encodable {
//        // Ensure BFF is configured
//        guard let bffBaseURL = bffBaseURL else {
//            throw HTTPClientError.bffNotConfigured
//        }
//        
//        // Build full URL
//        var urlString = bffBaseURL.hasSuffix("/") ? bffBaseURL : bffBaseURL + "/"
//        urlString += path.hasPrefix("/") ? String(path.dropFirst()) : path
//        
//        // Add query parameters
//        if let queryParameters = queryParameters, !queryParameters.isEmpty {
//            var components = URLComponents(string: urlString)
//            components?.queryItems = queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
//            urlString = components?.url?.absoluteString ?? urlString
//        }
//        
//        // Validate URL is BFF-only
//        try await allowedHostsPolicy.validateURL(urlString)
//        
//        guard let url = URL(string: urlString) else {
//            throw HTTPClientError.invalidURL(url: urlString)
//        }
//        
//        // Create request
//        var request = URLRequest(url: url)
//        request.httpMethod = method
//        
//        // Add body
//        if let body = body {
//            if let bodyData = body as? Data {
//                request.httpBody = bodyData
//            } else {
//                request.httpBody = try JSONEncoder().encode(body)
//            }
//            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        }
//        
//        // Add default headers
//        request.setValue("application/json", forHTTPHeaderField: "Accept")
//        
//        // Add correlation ID (automatic injection)
//        let finalCorrelationId = correlationId ?? CorrelationId()
//        request.setValue(finalCorrelationId.value, forHTTPHeaderField: CorrelationId.headerName)
//        
//        // Add trace ID if provided
//        if let traceId = traceId {
//            request.setValue(traceId, forHTTPHeaderField: "X-Trace-ID")
//        }
//        
//        // Add custom headers
//        if let headers = headers {
//            for (key, value) in headers {
//                request.setValue(value, forHTTPHeaderField: key)
//            }
//        }
//        
//        // Create trace context
//        let traceContext = await traceContextValidator.createTraceContext(
//            operationName: "\(method) \(path)",
//            parentSpanId: traceId
//        )
//        request.setValue(traceContext.traceId, forHTTPHeaderField: "X-Trace-ID")
//        request.setValue(traceContext.spanId, forHTTPHeaderField: "X-Span-ID")
//        
//        return request
//    }
//    
//    // MARK: - Request Execution
//    
//    private func execute<T: Decodable>(request: URLRequest) async throws -> T {
//        // Execute request
//        let (data, response) = try await session.data(for: request)
//        
//        // Validate response
//        guard let httpResponse = response as? HTTPURLResponse else {
//            throw HTTPClientError.invalidResponse
//        }
//        
//        // Check status code
//        guard (200...299).contains(httpResponse.statusCode) else {
//            throw HTTPClientError.httpError(statusCode: httpResponse.statusCode, data: data)
//        }
//        
//        // Decode response
//        do {
//            let decoder = JSONDecoder()
//            decoder.dateDecodingStrategy = .iso8601
//            return try decoder.decode(T.self, from: data)
//        } catch {
//            throw HTTPClientError.decodingError(error: error)
//        }
//    }
//    
//    // MARK: - Upload/Download
//    
//    /// Upload file
//    public func upload(
//        path: String,
//        fileURL: URL,
//        headers: [String: String]? = nil,
//        correlationId: CorrelationId? = nil,
//        traceId: String? = nil
//    ) async throws -> Data {
//        let request = try await buildRequest(
//            path: path,
//            method: "POST",
//            queryParameters: nil,
//            body: nil as Data?,
//            headers: headers,
//            correlationId: correlationId,
//            traceId: traceId
//        )
//        
//        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
//        
//        guard let httpResponse = response as? HTTPURLResponse else {
//            throw HTTPClientError.invalidResponse
//        }
//        
//        guard (200...299).contains(httpResponse.statusCode) else {
//            throw HTTPClientError.httpError(statusCode: httpResponse.statusCode, data: data)
//        }
//        
//        return data
//    }
//    
//    /// Download file
//    public func download(
//        path: String,
//        headers: [String: String]? = nil,
//        correlationId: CorrelationId? = nil,
//        traceId: String? = nil
//    ) async throws -> URL {
//        let request = try await buildRequest(
//            path: path,
//            method: "GET",
//            queryParameters: nil,
//            body: nil as Data?,
//            headers: headers,
//            correlationId: correlationId,
//            traceId: traceId
//        )
//        
//        let (url, response) = try await session.download(for: request)
//        
//        guard let httpResponse = response as? HTTPURLResponse else {
//            throw HTTPClientError.invalidResponse
//        }
//        
//        guard (200...299).contains(httpResponse.statusCode) else {
//            throw HTTPClientError.httpError(statusCode: httpResponse.statusCode, data: Data())
//        }
//        
//        return url
//    }
//}
//
//// MARK: - Errors
//
//public enum HTTPClientError: Error, LocalizedError {
//    case bffNotConfigured
//    case invalidBFFURL(url: String)
//    case invalidURL(url: String)
//    case invalidResponse
//    case httpError(statusCode: Int, data: Data)
//    case decodingError(error: Error)
//    case hostNotAllowed(host: String)
//    
//    public var errorDescription: String? {
//        switch self {
//        case .bffNotConfigured:
//            return "BFF base URL not configured. Call configureBFF() on app launch."
//        case .invalidBFFURL(let url):
//            return "Invalid BFF URL: \(url)"
//        case .invalidURL(let url):
//            return "Invalid URL: \(url)"
//        case .invalidResponse:
//            return "Invalid HTTP response"
//        case .httpError(let statusCode, _):
//            return "HTTP error: \(statusCode)"
//        case .decodingError(let error):
//            return "Decoding error: \(error.localizedDescription)"
//        case .hostNotAllowed(let host):
//            return "Host not allowed: \(host). Only BFF requests are permitted."
//        }
//    }
//}
//
//// MARK: - Response Types
//
//public struct EmptyResponse: Codable, Sendable {
//    public init() {}
//}
//
//public struct MessageResponse: Codable, Sendable {
//    public let message: String
//    
//    public init(message: String) {
//        self.message = message
//    }
//}
