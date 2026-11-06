//
//  CesarGateway.swift
//  CoreKit
//
//  Enforces that all AI/Copilot requests go through César service only

import Foundation
import WaanguCoreKit

public actor CesarGateway {
    
    public static let shared = CesarGateway()
    
    private var cesarServiceURL: URL?
    private var allowedAIProviders: Set<String> = []
    private let enforceGateway = true
    
    private init() {}
    
    // MARK: - Configuration
    
    public func configure(cesarURL: URL) {
        self.cesarServiceURL = cesarURL
        self.allowedAIProviders = Set([cesarURL.host].compactMap { $0 })
    }
    
    // MARK: - AI Request Validation
    
    public func validateAIRequest(_ request: AIRequest) async throws {
        guard enforceGateway else { return }
        
        guard let cesarURL = cesarServiceURL else {
            throw CesarError.notConfigured
        }
        
        // Check if request goes through César
        guard request.endpoint.contains(cesarURL.host ?? "") else {
            await logViolation(request: request)
            throw CesarError.directAICallDetected(
                provider: request.provider,
                endpoint: request.endpoint
            )
        }
        
        // Validate request has required César headers
        guard request.headers.contains(where: { $0.key == "X-Cesar-Gateway" }) else {
            throw CesarError.missingCesarHeader
        }
    }
    
    public func validatePrompt(_ prompt: String, context: AIContext) async throws -> ValidatedPrompt {
        guard let cesarURL = cesarServiceURL else {
            throw CesarError.notConfigured
        }
        
        // All prompts must be validated by César
        // Cannot bypass prompt injection filter
        let filtered = try await PromptInjectionFilter.shared.validate(prompt)
        
        switch filtered {
        case .safe(let input):
            return ValidatedPrompt(
                original: prompt,
                sanitized: input,
                cesarApproved: true,
                context: context
            )
            
        case .suspicious(let sanitized, let detections, let severity):
            if severity == .critical {
                throw CesarError.promptRejected(reason: "Critical threat detected")
            }
            
            return ValidatedPrompt(
                original: prompt,
                sanitized: sanitized,
                cesarApproved: true,
                context: context,
                warnings: detections.map { $0.pattern.type.rawValue }
            )
        }
    }
    
    // MARK: - Forbidden Patterns
    
    private let forbiddenDirectCalls = [
        "openai.com",
        "api.anthropic.com",
        "cohere.ai",
        "ai.google.dev",
        "api.together.xyz"
    ]
    
    public func checkForDirectAICalls(in url: String) throws {
        for forbidden in forbiddenDirectCalls {
            if url.contains(forbidden) {
                throw CesarError.directAICallDetected(
                    provider: forbidden,
                    endpoint: url
                )
            }
        }
    }
    
    // MARK: - Logging
    
    private func logViolation(request: AIRequest) async {
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: nil,
            metadata: [
                "violation": "cesar_bypass_attempt",
                "provider": request.provider,
                "endpoint": request.endpoint
            ]
        )
    }
    
    // MARK: - Types
    
    public struct AIRequest {
        public let provider: String
        public let endpoint: String
        public let headers: [String: String]
        public let prompt: String
        
        public init(provider: String, endpoint: String, headers: [String: String], prompt: String) {
            self.provider = provider
            self.endpoint = endpoint
            self.headers = headers
            self.prompt = prompt
        }
    }
    
    public struct AIContext {
        public let userId: String?
        public let conversationId: String?
        public let feature: String
        
        public init(userId: String?, conversationId: String?, feature: String) {
            self.userId = userId
            self.conversationId = conversationId
            self.feature = feature
        }
    }
    
    public struct ValidatedPrompt {
        public let original: String
        public let sanitized: String
        public let cesarApproved: Bool
        public let context: AIContext
        public let warnings: [String]
        
        public init(original: String, sanitized: String, cesarApproved: Bool, context: AIContext, warnings: [String] = []) {
            self.original = original
            self.sanitized = sanitized
            self.cesarApproved = cesarApproved
            self.context = context
            self.warnings = warnings
        }
    }
    
    public enum CesarError: Error, LocalizedError {
        case notConfigured
        case directAICallDetected(provider: String, endpoint: String)
        case missingCesarHeader
        case promptRejected(reason: String)
        
        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "César gateway not configured"
            case .directAICallDetected(let provider, let endpoint):
                return "Direct AI call detected: \(provider) at \(endpoint). All AI requests must go through César."
            case .missingCesarHeader:
                return "Missing X-Cesar-Gateway header. Request must be routed through César."
            case .promptRejected(let reason):
                return "Prompt rejected by César: \(reason)"
            }
        }
    }
}
