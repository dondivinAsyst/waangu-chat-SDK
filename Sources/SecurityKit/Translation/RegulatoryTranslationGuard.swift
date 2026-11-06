//
//  RegulatoryTranslationGuard.swift
//  CoreKit
//
//  Ensures translation compliance with regulations (GDPR, content policies)

import Foundation
import WaanguCoreKit
import CryptoKit

public actor RegulatoryTranslationGuard {
    
    public static let shared = RegulatoryTranslationGuard()
    
    private var translationLogs: [TranslationLog] = []
    private let maxLogSize = 10000
    private var piiPatterns: [PIIPattern] = []
    private var georgesLandryServiceURL: URL?
    private let enforceGateway = true
    
    private init() {
        setupPIIPatterns()
    }
    
    // MARK: - Gateway Configuration
    
    public func configureGeorgesLandryGateway(serviceURL: URL) {
        self.georgesLandryServiceURL = serviceURL
    }
    
    public func validateTranslationRequest(_ request: TranslationRequest) throws {
        guard enforceGateway else { return }
        
        guard let serviceURL = georgesLandryServiceURL else {
            throw GuardError.georgesLandryNotConfigured
        }
        
        // All regulatory translations must go through Georges/Landry
        guard request.endpoint.contains(serviceURL.host ?? "") else {
            throw GuardError.localRegulatoryTranslationForbidden(
                sourceLanguage: request.sourceLanguage,
                targetLanguage: request.targetLanguage
            )
        }
        
        // Validate request has Georges/Landry header
        guard request.headers.contains(where: { $0.key == "X-GeorgesLandry-Gateway" }) else {
            throw GuardError.missingGeorgesLandryHeader
        }
    }
    
    // MARK: - PII Patterns
    
    private func setupPIIPatterns() {
        piiPatterns = [
            // Email addresses
            PIIPattern(
                regex: try! NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}"),
                type: .email,
                replacement: "[EMAIL]"
            ),
            
            // Phone numbers (international)
            PIIPattern(
                regex: try! NSRegularExpression(pattern: "\\+?[1-9]\\d{1,14}|\\(?\\d{3}\\)?[-.\\s]?\\d{3}[-.\\s]?\\d{4}"),
                type: .phone,
                replacement: "[PHONE]"
            ),
            
            // Credit card numbers
            PIIPattern(
                regex: try! NSRegularExpression(pattern: "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b"),
                type: .creditCard,
                replacement: "[CARD]"
            ),
            
            // SSN (US)
            PIIPattern(
                regex: try! NSRegularExpression(pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b"),
                type: .ssn,
                replacement: "[SSN]"
            ),
            
            // IP addresses
            PIIPattern(
                regex: try! NSRegularExpression(pattern: "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b"),
                type: .ipAddress,
                replacement: "[IP]"
            ),
            
            // URLs with potential PII
            PIIPattern(
                regex: try! NSRegularExpression(pattern: "https?://[^\\s]+"),
                type: .url,
                replacement: "[URL]"
            )
        ]
    }
    
    // MARK: - Public API
    
    public func validateAndPrepare(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        userId: String?,
        context: TranslationContext
    ) async throws -> PreparedTranslation {
        
        // Validate input
        guard !text.isEmpty else {
            throw GuardError.emptyInput
        }
        
        guard text.count <= 5000 else {
            throw GuardError.textTooLong(length: text.count)
        }
        
        // Detect and filter PII
        let piiDetections = detectPII(in: text)
        let sanitized = sanitizePII(text, detections: piiDetections)
        
        // Check content policy
        let contentViolations = await checkContentPolicy(sanitized)
        
        if !contentViolations.isEmpty {
            throw GuardError.contentPolicyViolation(violations: contentViolations)
        }
        
        // Create audit log
        let log = TranslationLog(
            id: UUID().uuidString,
            timestamp: Date(),
            userId: userId,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            originalLength: text.count,
            sanitizedLength: sanitized.count,
            piiDetected: piiDetections,
            context: context,
            status: .prepared
        )
        
        await logTranslation(log)
        
        return PreparedTranslation(
            id: log.id,
            sanitizedText: sanitized,
            piiDetections: piiDetections,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }
    
    public func recordTranslationResult(
        id: String,
        translatedText: String,
        success: Bool,
        error: String? = nil
    ) async {
        
        if let index = translationLogs.firstIndex(where: { $0.id == id }) {
            var log = translationLogs[index]
            log.status = success ? .completed : .failed
            log.translatedLength = translatedText.count
            log.error = error
            log.completedAt = Date()
            translationLogs[index] = log
        }
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: success ? .dataViewed : .errorOccurred,
            category: .system,
            metadata: [
                "translation_id": id,
                "success": "\(success)",
                "error": error ?? "none"
            ],
            severity: success ? .info : .warning
        )
    }
    
    public func getTranslationLogs(
        userId: String? = nil,
        limit: Int = 100
    ) async -> [TranslationLog] {
        var logs = translationLogs
        
        if let userId = userId {
            logs = logs.filter { $0.userId == userId }
        }
        
        return Array(logs.prefix(limit))
    }
    
    public func generateComplianceReport(
        startDate: Date,
        endDate: Date
    ) async -> ComplianceReport {
        
        let filtered = translationLogs.filter {
            $0.timestamp >= startDate && $0.timestamp <= endDate
        }
        
        let totalTranslations = filtered.count
        let withPII = filtered.filter { !$0.piiDetected.isEmpty }.count
        let failed = filtered.filter { $0.status == .failed }.count
        
        var piiByType: [PIIType: Int] = [:]
        for log in filtered {
            for detection in log.piiDetected {
                piiByType[detection.type, default: 0] += 1
            }
        }
        
        return ComplianceReport(
            startDate: startDate,
            endDate: endDate,
            totalTranslations: totalTranslations,
            translationsWithPII: withPII,
            failedTranslations: failed,
            piiDetectionsByType: piiByType,
            averageTextLength: filtered.map(\.originalLength).reduce(0, +) / max(totalTranslations, 1)
        )
    }
    
    public func clearLogs(olderThan date: Date) async {
        translationLogs.removeAll { $0.timestamp < date }
    }
    
    // MARK: - PII Detection
    
    private func detectPII(in text: String) -> [PIIDetection] {
        var detections: [PIIDetection] = []
        
        for pattern in piiPatterns {
            let range = NSRange(text.startIndex..., in: text)
            let matches = pattern.regex.matches(in: text, range: range)
            
            for match in matches {
                if let matchRange = Range(match.range, in: text) {
                    let matched = String(text[matchRange])
                    
                    // Hash the PII for audit trail
                    let hash = SHA256.hash(data: Data(matched.utf8))
                    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
                    
                    detections.append(PIIDetection(
                        type: pattern.type,
                        location: match.range.location,
                        length: match.range.length,
                        hash: String(hashString.prefix(16))
                    ))
                }
            }
        }
        
        return detections
    }
    
    private func sanitizePII(_ text: String, detections: [PIIDetection]) -> String {
        var sanitized = text
        
        // Sort by location (reverse) to maintain indices
        let sorted = detections.sorted { $0.location > $1.location }
        
        for detection in sorted {
            let range = NSRange(location: detection.location, length: detection.length)
            if let stringRange = Range(range, in: sanitized),
               let pattern = piiPatterns.first(where: { $0.type == detection.type }) {
                sanitized.replaceSubrange(stringRange, with: pattern.replacement)
            }
        }
        
        return sanitized
    }
    
    // MARK: - Content Policy
    
    private func checkContentPolicy(_ text: String) async -> [ContentViolation] {
        var violations: [ContentViolation] = []
        
        // Hate speech patterns
        let hatePatterns = [
            "\\b(hate|kill|attack)\\s+(all|every)\\s+\\w+",
            "\\b(racist|sexist|homophobic)\\b"
        ]
        
        for patternString in hatePatterns {
            if let regex = try? NSRegularExpression(pattern: patternString, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, range: range) != nil {
                    violations.append(ContentViolation(
                        type: .hateSpeech,
                        severity: .high
                    ))
                }
            }
        }
        
        // Violence patterns
        let violencePatterns = [
            "\\b(bomb|weapon|explosive)\\s+(instructions?|how to|guide)",
            "\\b(murder|assassinate|harm)\\b"
        ]
        
        for patternString in violencePatterns {
            if let regex = try? NSRegularExpression(pattern: patternString, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, range: range) != nil {
                    violations.append(ContentViolation(
                        type: .violence,
                        severity: .critical
                    ))
                }
            }
        }
        
        return violations
    }
    
    // MARK: - Logging
    
    private func logTranslation(_ log: TranslationLog) async {
        translationLogs.insert(log, at: 0)
        
        if translationLogs.count > maxLogSize {
            translationLogs.removeLast()
        }
        
        // GDPR compliance: log the translation request
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "translation_id": log.id,
                "source_lang": log.sourceLanguage,
                "target_lang": log.targetLanguage,
                "pii_detected": "\(!log.piiDetected.isEmpty)",
                "context": log.context.rawValue
            ],
            severity: .info
        )
    }
    
    // MARK: - Types
    
    public struct PIIPattern {
        let regex: NSRegularExpression
        let type: PIIType
        let replacement: String
    }
    
    public enum PIIType: String, Codable {
        case email
        case phone
        case creditCard
        case ssn
        case ipAddress
        case url
        case name
        case address
    }
    
    public struct PIIDetection: Codable {
        let type: PIIType
        let location: Int
        let length: Int
        let hash: String // SHA256 hash for audit trail
    }
    
    public enum TranslationContext: String, Codable {
        case chat
        case story
        case profile
        case settings
        case aiAssistant
    }
    
    public struct TranslationLog: Codable {
        let id: String
        let timestamp: Date
        let userId: String?
        let sourceLanguage: String
        let targetLanguage: String
        let originalLength: Int
        let sanitizedLength: Int
        let piiDetected: [PIIDetection]
        let context: TranslationContext
        var status: TranslationStatus
        var translatedLength: Int?
        var error: String?
        var completedAt: Date?
    }
    
    public enum TranslationStatus: String, Codable {
        case prepared
        case completed
        case failed
    }
    
    public struct PreparedTranslation {
        public let id: String
        public let sanitizedText: String
        public let piiDetections: [PIIDetection]
        public let sourceLanguage: String
        public let targetLanguage: String
    }
    
    public struct ContentViolation: Codable {
        let type: ViolationType
        let severity: Severity
        
        public enum ViolationType: String, Codable {
            case hateSpeech
            case violence
            case sexualContent
            case spam
            case misinformation
        }
        
        public enum Severity: String, Codable {
            case low
            case medium
            case high
            case critical
        }
    }
    
    public struct ComplianceReport: Codable {
        let startDate: Date
        let endDate: Date
        let totalTranslations: Int
        let translationsWithPII: Int
        let failedTranslations: Int
        let piiDetectionsByType: [PIIType: Int]
        let averageTextLength: Int
    }
    
    public enum GuardError: Error, LocalizedError {
        case emptyInput
        case textTooLong(length: Int)
        case contentPolicyViolation(violations: [ContentViolation])
        case georgesLandryNotConfigured
        case localRegulatoryTranslationForbidden(sourceLanguage: String, targetLanguage: String)
        case missingGeorgesLandryHeader
        
        public var errorDescription: String? {
            switch self {
            case .emptyInput:
                return "Translation input cannot be empty"
            case .textTooLong(let length):
                return "Text too long: \(length) characters (max 5000)"
            case .contentPolicyViolation(let violations):
                return "Content policy violation: \(violations.count) issues detected"
            case .georgesLandryNotConfigured:
                return "Georges/Landry translation gateway not configured"
            case .localRegulatoryTranslationForbidden(let source, let target):
                return "Local regulatory translation forbidden: \(source) → \(target). Must use Georges/Landry service."
            case .missingGeorgesLandryHeader:
                return "Missing X-GeorgesLandry-Gateway header"
            }
        }
    }
    
    public struct TranslationRequest {
        public let endpoint: String
        public let headers: [String: String]
        public let sourceLanguage: String
        public let targetLanguage: String
        public let text: String
        
        public init(endpoint: String, headers: [String: String], sourceLanguage: String, targetLanguage: String, text: String) {
            self.endpoint = endpoint
            self.headers = headers
            self.sourceLanguage = sourceLanguage
            self.targetLanguage = targetLanguage
            self.text = text
        }
    }
}
