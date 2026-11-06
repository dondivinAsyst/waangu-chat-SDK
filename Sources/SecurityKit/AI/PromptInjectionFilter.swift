//
//  PromptInjectionFilter.swift
//  CoreKit
//
//  Filters and detects prompt injection attacks in AI systems

import Foundation
import WaanguCoreKit
import CryptoKit

public actor PromptInjectionFilter: PromptInjectionFilterProtocol {
    
    public static let shared = PromptInjectionFilter()
    
    private var detectedAttacks: [PromptInjectionAttackLog] = []
    private let maxLogSize = 1000
    
    private init() {}
    
    // MARK: - Attack Patterns
    
    private let injectionPatterns: [InjectionPattern] = [
        // System prompt manipulation
        //
        // Jusqu'à 40 caractères entre « ignore » et la cible, dans la même
        // phrase (B40) : l'ancienne expression n'admettait qu'un mot, et laissait
        // passer « ignore all previous instructions » comme « ignore all policy »
        // (Harness Bloc 3 §43). Le vocabulaire couvre aussi les politiques.
        InjectionPattern(
            regex: try! NSRegularExpression(pattern: "\\bignore\\b[^.\\n]{0,40}?\\b(instructions?|prompts?|rules?|polic(y|ies)|guidelines?|safeguards?|restrictions?)\\b", options: .caseInsensitive),
            severity: .critical,
            type: .systemPromptOverride
        ),
        // Contournement de la chaîne gouvernée : appeler un partenaire, un
        // adaptateur EIG ou le grand livre « directement » (Bloc 3 §47, B40).
        // Signalé, pas bloqué : la vraie garantie est qu'aucun outil ne
        // s'exécute sur l'appareil.
        InjectionPattern(
            regex: try! NSRegularExpression(pattern: "\\b(EIG|partner|adapter|ledger|admin route)\\b[^.\\n]{0,40}?\\bdirectly\\b|\\bdirectly\\b[^.\\n]{0,40}?\\b(EIG|partner|adapter|ledger)\\b", options: .caseInsensitive),
            severity: .high,
            type: .jailbreak
        ),
        InjectionPattern(
            regex: try! NSRegularExpression(pattern: "you are now (a|an) (different|new)", options: .caseInsensitive),
            severity: .critical,
            type: .roleManipulation
        ),
        InjectionPattern(
            regex: try! NSRegularExpression(pattern: "(reveal|show|display|tell me) (your|the) (system|original) (prompt|instructions?)", options: .caseInsensitive),
            severity: .high,
            type: .promptLeakage
        ),
        
        // Context manipulation
        InjectionPattern(
            regex: try! NSRegularExpression(pattern: "\\[\\s*system\\s*\\]|\\[\\s*assistant\\s*\\]|\\[\\s*user\\s*\\]", options: .caseInsensitive),
            severity: .high,
            type: .contextInjection
        ),
        InjectionPattern(
            regex: try! NSRegularExpression(pattern: "<\\|im_start\\|>|<\\|im_end\\|>|<\\|endoftext\\|>", options: .caseInsensitive),
            severity: .critical,
            type: .tokenInjection
        ),
        
        // Jailbreak attempts
        InjectionPattern(
            regex: try! NSRegularExpression(pattern: "(DAN|developer mode|god mode|admin mode|root access)", options: .caseInsensitive),
            severity: .critical,
            type: .jailbreak
        ),
        InjectionPattern(
            regex: try! NSRegularExpression(pattern: "act as if|pretend (you are|to be)|simulate", options: .caseInsensitive),
            severity: .medium,
            type: .rolePlay
        ),
        
        // Code injection
        InjectionPattern(
            regex: try! NSRegularExpression(pattern: "```\\s*(python|javascript|bash|sh|sql)", options: .caseInsensitive),
            severity: .high,
            type: .codeInjection
        ),
        
        // Translation-specific attacks
        InjectionPattern(
            regex: try! NSRegularExpression(pattern: "translate.*then (execute|run|eval)", options: .caseInsensitive),
            severity: .critical,
            type: .translationChaining
        )
    ]
    
    // MARK: - Public API
    
    public func validate(_ input: String) async throws -> PromptInjectionValidationResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check length
        guard trimmed.count > 0 else {
            throw PromptInjectionFilterError.emptyInput
        }
        
        guard trimmed.count <= 10000 else {
            throw PromptInjectionFilterError.inputTooLong(length: trimmed.count)
        }
        
        // Detect attacks
        let detections = detectInjections(in: trimmed)
        
        if !detections.isEmpty {
            let log = PromptInjectionAttackLog(
                timestamp: Date(),
                input: String(trimmed.prefix(500)),
                detections: detections
            )
            await logAttack(log)
            
            let highestSeverity = detections.map(\.pattern.severity).max() ?? .low
            
            if highestSeverity == .critical {
                throw PromptInjectionFilterError.criticalThreatDetected(detections: detections)
            }
            
            return .suspicious(
                sanitized: sanitize(trimmed, detections: detections),
                detections: detections,
                severity: highestSeverity
            )
        }
        
        return .safe(input: trimmed)
    }
    
    public func sanitize(_ input: String) async -> String {
        let detections = detectInjections(in: input)
        return sanitize(input, detections: detections)
    }
    
    public func getAttackLogs(limit: Int = 100) async -> [PromptInjectionAttackLog] {
        Array(detectedAttacks.prefix(limit))
    }
    
    public func clearLogs() async {
        detectedAttacks.removeAll()
    }
    
    // MARK: - Detection
    
    private func detectInjections(in input: String) -> [PromptInjectionDetection] {
        var detections: [PromptInjectionDetection] = []
        
        for pattern in injectionPatterns {
            let range = NSRange(input.startIndex..., in: input)
            let matches = pattern.regex.matches(in: input, range: range)
            
            for match in matches {
                if let matchRange = Range(match.range, in: input) {
                    let severityRawValue = pattern.severity.rawValue
                    let typeRawValue = pattern.type.rawValue
                    
                    let protocolSeverity: PromptInjectionSeverity
                    switch severityRawValue {
                    case 1: protocolSeverity = .low
                    case 2: protocolSeverity = .medium
                    case 3: protocolSeverity = .high
                    case 4: protocolSeverity = .critical
                    default: protocolSeverity = .low
                    }
                    
                    let protocolType: PromptInjectionAttackType
                    switch pattern.type {
                    case .systemPromptOverride: protocolType = .systemPromptOverride
                    case .roleManipulation: protocolType = .roleManipulation
                    case .promptLeakage: protocolType = .promptLeakage
                    case .contextInjection: protocolType = .contextInjection
                    case .tokenInjection: protocolType = .tokenInjection
                    case .jailbreak: protocolType = .jailbreak
                    case .rolePlay: protocolType = .rolePlay
                    case .codeInjection: protocolType = .codeInjection
                    case .translationChaining: protocolType = .translationChaining
                    }
                    
                    detections.append(PromptInjectionDetection(
                        pattern: PromptInjectionDetection.PatternInfo(
                            severity: protocolSeverity,
                            type: protocolType
                        ),
                        matchedText: String(input[matchRange]),
                        location: match.range.location
                    ))
                }
            }
        }
        
        return detections
    }
    
    // MARK: - Sanitization
    
    private func sanitize(_ input: String, detections: [PromptInjectionDetection]) -> String {
        var sanitized = input
        
        // Sort by location (reverse) to maintain indices
        let sorted = detections.sorted { $0.location > $1.location }
        
        for detection in sorted {
            let range = NSRange(location: detection.location, length: detection.matchedText.count)
            if let stringRange = Range(range, in: sanitized) {
                sanitized.replaceSubrange(stringRange, with: "[FILTERED]")
            }
        }
        
        return sanitized
    }
    
    // MARK: - Logging
    
    private func logAttack(_ log: PromptInjectionAttackLog) async {
        detectedAttacks.insert(log, at: 0)
        
        if detectedAttacks.count > maxLogSize {
            detectedAttacks.removeLast()
        }
        
        // Integrate with audit system
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: nil,
            metadata: [
                "violation_type": "prompt_injection",
                "severity": "\(log.highestSeverity.rawValue)",
                "detection_count": "\(log.detections.count)"
            ]
        )
    }
}

// MARK: - Internal Types

/// Internal injection pattern
public struct InjectionPattern {
    let regex: NSRegularExpression
    let severity: Severity
    let type: AttackType
}

/// Internal severity enum
public enum Severity: Int, Comparable, Codable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Internal attack type enum
public enum AttackType: String, Codable {
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
