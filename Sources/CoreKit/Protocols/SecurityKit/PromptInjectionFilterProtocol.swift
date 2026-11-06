//
//  PromptInjectionFilterProtocol.swift
//  CoreKit
//
//  Protocol abstraction for PromptInjectionFilter

import Foundation

/// Attack severity levels
public enum PromptInjectionSeverity: Int, Comparable, Codable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    public static func < (lhs: PromptInjectionSeverity, rhs: PromptInjectionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Attack types
public enum PromptInjectionAttackType: String, Codable {
    case systemPromptOverride
    case roleManipulation
    case promptLeakage
    case contextInjection
    case tokenInjection
    case jailbreak
    case rolePlay
    case codeInjection
    case translationChaining
}

/// Detection result
public struct PromptInjectionDetection: Codable {
   public let pattern: PatternInfo
   public let matchedText: String
   public let location: Int
    
    public init(pattern: PatternInfo, matchedText: String, location: Int) {
        self.pattern = pattern
        self.matchedText = matchedText
        self.location = location
    }
    
    public struct PatternInfo: Codable {
        public let severity: PromptInjectionSeverity
        public let type: PromptInjectionAttackType
        
        public init(severity: PromptInjectionSeverity, type: PromptInjectionAttackType) {
            self.severity = severity
            self.type = type
        }
    }
}

/// Attack log entry
public struct PromptInjectionAttackLog: Codable {
    public let timestamp: Date
    public let input: String
    public let detections: [PromptInjectionDetection]
    
    public init(timestamp: Date, input: String, detections: [PromptInjectionDetection]) {
        self.timestamp = timestamp
        self.input = input
        self.detections = detections
    }
    
    public var highestSeverity: PromptInjectionSeverity {
        detections.map(\.pattern.severity).max() ?? .low
    }
}

/// Validation result
public enum PromptInjectionValidationResult {
    case safe(input: String)
    case suspicious(sanitized: String, detections: [PromptInjectionDetection], severity: PromptInjectionSeverity)
}

/// Filter errors
public enum PromptInjectionFilterError: Error, LocalizedError {
    case emptyInput
    case inputTooLong(length: Int)
    case criticalThreatDetected(detections: [PromptInjectionDetection])
    
    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Input cannot be empty"
        case .inputTooLong(let length):
            return "Input too long: \(length) characters (max 10000)"
        case .criticalThreatDetected(let detections):
            return "Critical security threat detected: \(detections.count) patterns matched"
        }
    }
}

public protocol PromptInjectionFilterProtocol: Sendable {
    /// Validate and filter input
    func validate(_ input: String) async throws -> PromptInjectionValidationResult
    
    /// Sanitize input by removing detected patterns
    func sanitize(_ input: String) async -> String
    
    /// Get attack logs
    func getAttackLogs(limit: Int) async -> [PromptInjectionAttackLog]
    
    /// Clear attack logs
    func clearLogs() async
}
