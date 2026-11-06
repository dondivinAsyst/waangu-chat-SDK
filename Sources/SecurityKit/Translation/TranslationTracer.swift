//
//  TranslationTracer.swift
//  CoreKit
//
//  Traceable translation operations
//  RULE: Traduction traçable

import Foundation
import WaanguCoreKit

public actor TranslationTracer {
    
    public static let shared = TranslationTracer()
    
    private var translations: [TranslationRecord] = []
    
    private init() {}
    
    // MARK: - Translation Tracing
    
    /// Records translation for traceability
    /// RULE: Traduction traçable
    public func recordTranslation(
        sourceText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        translationService: String,
        userId: String?,
        context: TranslationContext
    ) async -> String {
        
        let translationId = UUID().uuidString
        
        let record = TranslationRecord(
            id: translationId,
            sourceText: sourceText,
            translatedText: translatedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            translationService: translationService,
            userId: userId,
            context: context,
            timestamp: Date()
        )
        
        translations.append(record)
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "action": "translation_recorded",
                "translation_id": translationId,
                "source_lang": sourceLanguage,
                "target_lang": targetLanguage,
                "service": translationService,
                "context": context.rawValue
            ],
            severity: .info
        )
        
        return translationId
    }
    
    /// Gets translation by ID
    public func getTranslation(_ translationId: String) -> TranslationRecord? {
        translations.first { $0.id == translationId }
    }
    
    /// Gets translations for user
    public func getTranslationsForUser(_ userId: String) -> [TranslationRecord] {
        translations.filter { $0.userId == userId }
    }
    
    /// Gets translations by context
    public func getTranslationsByContext(_ context: TranslationContext) -> [TranslationRecord] {
        translations.filter { $0.context == context }
    }
    
    /// Generates translation audit trail
    public func generateAuditTrail(
        translationId: String
    ) -> TranslationAuditTrail? {
        
        guard let record = getTranslation(translationId) else {
            return nil
        }
        
        return TranslationAuditTrail(
            translationId: translationId,
            sourceText: record.sourceText,
            translatedText: record.translatedText,
            sourceLanguage: record.sourceLanguage,
            targetLanguage: record.targetLanguage,
            translationService: record.translationService,
            userId: record.userId,
            context: record.context,
            timestamp: record.timestamp,
            verifiable: true
        )
    }
    
    /// Validates translation traceability
    public func validateTraceability(translationId: String) throws {
        guard let record = getTranslation(translationId) else {
            throw TranslationError.translationNotFound(id: translationId)
        }
        
        // Validate required fields
        guard !record.sourceText.isEmpty else {
            throw TranslationError.missingSourceText
        }
        
        guard !record.translatedText.isEmpty else {
            throw TranslationError.missingTranslatedText
        }
        
        guard !record.translationService.isEmpty else {
            throw TranslationError.missingTranslationService
        }
    }
    
    // MARK: - Types
    
    public struct TranslationRecord {
        public let id: String
        public let sourceText: String
        public let translatedText: String
        public let sourceLanguage: String
        public let targetLanguage: String
        public let translationService: String
        public let userId: String?
        public let context: TranslationContext
        public let timestamp: Date
    }
    
    public struct TranslationAuditTrail {
        public let translationId: String
        public let sourceText: String
        public let translatedText: String
        public let sourceLanguage: String
        public let targetLanguage: String
        public let translationService: String
        public let userId: String?
        public let context: TranslationContext
        public let timestamp: Date
        public let verifiable: Bool
    }
    
    public enum TranslationContext: String, Codable {
        case chatMessage
        case userProfile
        case productDescription
        case legalDocument
        case medicalContent
        case financialContent
        case generalContent
    }
    
    public enum TranslationError: Error, LocalizedError {
        case translationNotFound(id: String)
        case missingSourceText
        case missingTranslatedText
        case missingTranslationService
        
        public var errorDescription: String? {
            switch self {
            case .translationNotFound(let id):
                return "Translation not found: \(id)"
            case .missingSourceText:
                return "Source text is required for traceability"
            case .missingTranslatedText:
                return "Translated text is required for traceability"
            case .missingTranslationService:
                return "Translation service is required for traceability"
            }
        }
    }
}
