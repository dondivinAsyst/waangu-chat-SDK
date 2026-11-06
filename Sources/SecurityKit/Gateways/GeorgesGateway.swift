//
//  GeorgesGateway.swift
//  SecurityKit
//
//  Gateway for Georges service (Translation)
//  Enforces all translations through Georges backend
//

import Foundation
import WaanguCoreKit

/// Georges Gateway - Translation Service
/// All translations must go through Georges
public actor GeorgesGateway {
    
    public static let shared = GeorgesGateway()
    
    private var georgesServiceURL: URL?
    private var isConfigured = false
    
    private init() {}
    
    public struct TranslationRequest: Sendable {
        public let requestId: String
        public let text: String
        public let sourceLanguage: String
        public let targetLanguage: String
        public let context: TranslationContext
        public let timestamp: Date
        
        public init(requestId: String, text: String, sourceLanguage: String, targetLanguage: String, context: TranslationContext, timestamp: Date) {
            self.requestId = requestId
            self.text = text
            self.sourceLanguage = sourceLanguage
            self.targetLanguage = targetLanguage
            self.context = context
            self.timestamp = timestamp
        }
    }
    
    public struct TranslationResult: Sendable {
        public let requestId: String
        public let translatedText: String
        public let confidence: Double
        
        public init(requestId: String, translatedText: String, confidence: Double) {
            self.requestId = requestId
            self.translatedText = translatedText
            self.confidence = confidence
        }
    }
    
    public enum TranslationContext: String, Sendable {
        case chatMessage
        case userProfile
        case productDescription
        case legalDocument
        case medicalContent
        case financialContent
        case generalContent
    }
    
    public enum GeorgesError: Error, Sendable {
        case notConfigured
        case invalidURL
        case unsupportedLanguage
        case networkError
    }
    
    // MARK: - Configuration
    
    public func configure(serviceURL: URL) {
        self.georgesServiceURL = serviceURL
        self.isConfigured = true
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "configure_georges_gateway", "url": serviceURL.absoluteString]
            )
        }
    }
    
    // MARK: - Translation Operations
    
    public func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        context: TranslationContext = .generalContent
    ) async throws -> TranslationResult {
        guard isConfigured, let serviceURL = georgesServiceURL else {
            throw GeorgesError.notConfigured
        }
        
        let request = TranslationRequest(
            requestId: UUID().uuidString,
            text: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            context: context,
            timestamp: Date()
        )
        
        let result = try await performTranslation(request: request, serviceURL: serviceURL)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "operation": "translate",
                "requestId": request.requestId,
                "from": sourceLanguage,
                "to": targetLanguage,
                "context": context.rawValue
            ]
        )
        
        return result
    }
    
    // MARK: - Private Helpers
    
    private func performTranslation(request: TranslationRequest, serviceURL: URL) async throws -> TranslationResult {
        // In production: actual HTTP request to Georges service
        // For now: mock result
        return TranslationResult(
            requestId: request.requestId,
            translatedText: request.text,
            confidence: 0.95
        )
    }
}
