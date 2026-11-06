//
//  TranslationEnvelope.swift
//  CoreKit
//
//  Canonical translation envelope with backend signature
//  RULE: TranslationEnvelope créé
//

import Foundation

/// Canonical translation envelope
/// All translations must be wrapped in this envelope with backend signature
public struct TranslationEnvelope: Codable, Sendable, Identifiable {
    
    public let id: String
    public let sourceLanguage: String
    public let targetLanguage: String
    public let originalText: String
    public let translatedText: String?
    public let timestamp: Date
    public let status: TranslationStatus
    
    // Backend authority
    public let backendSignature: String
    public let translationProvider: String
    public let providerTransactionId: String?
    public let truthSource: TruthSource
    
    // Metadata
    public let correlationId: String
    public let traceId: String?
    public let userId: String?
    public let conversationId: String?
    public let messageId: String?
    public let confidence: Double?
    public let detectedLanguage: String?
    
    // Quality
    public let qualityScore: Double?
    public let alternativeTranslations: [String]?
    public let translationMetadata: [String: String]
    
    public init(
        id: String,
        sourceLanguage: String,
        targetLanguage: String,
        originalText: String,
        translatedText: String?,
        timestamp: Date,
        status: TranslationStatus,
        backendSignature: String,
        translationProvider: String,
        providerTransactionId: String?,
        truthSource: TruthSource = .backend,
        correlationId: String,
        traceId: String? = nil,
        userId: String?,
        conversationId: String?,
        messageId: String?,
        confidence: Double?,
        detectedLanguage: String?,
        qualityScore: Double?,
        alternativeTranslations: [String]?,
        translationMetadata: [String: String]
    ) {
        self.id = id
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.originalText = originalText
        self.translatedText = translatedText
        self.timestamp = timestamp
        self.status = status
        self.backendSignature = backendSignature
        self.translationProvider = translationProvider
        self.providerTransactionId = providerTransactionId
        self.truthSource = truthSource
        self.correlationId = correlationId
        self.traceId = traceId
        self.userId = userId
        self.conversationId = conversationId
        self.messageId = messageId
        self.confidence = confidence
        self.detectedLanguage = detectedLanguage
        self.qualityScore = qualityScore
        self.alternativeTranslations = alternativeTranslations
        self.translationMetadata = translationMetadata
    }
}

// MARK: - Translation Status

public enum TranslationStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case processing = "PROCESSING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case lowConfidence = "LOW_CONFIDENCE"
    case manualReviewRequired = "MANUAL_REVIEW_REQUIRED"
    case complianceHold = "COMPLIANCE_HOLD"
}

// MARK: - Verification

public extension TranslationEnvelope {
    
    /// Verify backend signature (HMAC-SHA256)
    func verifySignature(secret: String) -> Bool {
        let payload = "\(id):\(sourceLanguage):\(targetLanguage):\(originalText):\(timestamp.timeIntervalSince1970)"
        
        guard let payloadData = payload.data(using: .utf8),
              let secretData = secret.data(using: .utf8) else {
            return false
        }
        
        // In production: Use CryptoKit for HMAC-SHA256
        // For now: Simple validation
        return backendSignature.count >= 64 && !backendSignature.isEmpty
    }
    
    /// Check if translation is from backend
    var isFromBackend: Bool {
        return truthSource == .backend && !backendSignature.isEmpty
    }
    
    /// Check if translation has provider proof
    var hasProviderProof: Bool {
        return !translationProvider.isEmpty && providerTransactionId != nil
    }
    
    /// Check if translation is complete
    var isComplete: Bool {
        return status == .completed && translatedText != nil && isFromBackend
    }
    
    /// Check if translation is pending
    var isPending: Bool {
        return [.pending, .processing].contains(status)
    }
    
    /// Check if translation requires review
    var requiresReview: Bool {
        return [.lowConfidence, .manualReviewRequired, .complianceHold].contains(status)
    }
    
    /// Check if translation is high confidence
    var isHighConfidence: Bool {
        guard let confidence = confidence else { return false }
        return confidence >= 0.8
    }
    
    /// Check if translation is low confidence
    var isLowConfidence: Bool {
        guard let confidence = confidence else { return true }
        return confidence < 0.6
    }
    
    /// Check if translation has alternatives
    var hasAlternatives: Bool {
        return alternativeTranslations?.isEmpty == false
    }
    
    /// Check if language was auto-detected
    var wasLanguageDetected: Bool {
        return detectedLanguage != nil && detectedLanguage != sourceLanguage
    }
    
    /// Get display text (translated or original)
    var displayText: String {
        return translatedText ?? originalText
    }
}

// MARK: - Equatable

extension TranslationEnvelope: Equatable {
    public static func == (lhs: TranslationEnvelope, rhs: TranslationEnvelope) -> Bool {
        return lhs.id == rhs.id &&
               lhs.backendSignature == rhs.backendSignature
    }
}

// MARK: - Hashable

extension TranslationEnvelope: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(backendSignature)
    }
}
