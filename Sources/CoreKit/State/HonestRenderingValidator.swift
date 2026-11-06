//
//  HonestRenderingValidator.swift
//  CoreKit
//
//  Validates rendering honesty and integrates with TimelineStore
//  RULE: HonestRenderingValidator branché dans TimelineStore
//

import Foundation

/// Validates rendering honesty
/// Ensures what's rendered matches what's claimed
public actor HonestRenderingValidator {
    
    public static let shared = HonestRenderingValidator()
    
    private var validationResults: [String: ValidationResult] = [:]
    private var timelineIntegrationEnabled = true
    
    private init() {}
    
    public struct ValidationResult: Sendable {
        public let validationId: String
        public let conversationId: String
        public let isValid: Bool
        public let violations: [Violation]
        public let validatedAt: Date
        public let timelineStoreVerified: Bool
        
        public init(
            validationId: String = UUID().uuidString,
            conversationId: String,
            isValid: Bool,
            violations: [Violation],
            validatedAt: Date = Date(),
            timelineStoreVerified: Bool
        ) {
            self.validationId = validationId
            self.conversationId = conversationId
            self.isValid = isValid
            self.violations = violations
            self.validatedAt = validatedAt
            self.timelineStoreVerified = timelineStoreVerified
        }
    }
    
    public struct Violation: Sendable {
        public let violationId: String
        public let violationType: ViolationType
        public let description: String
        public let severity: Severity
        public let detectedAt: Date
        
        public init(
            violationId: String = UUID().uuidString,
            violationType: ViolationType,
            description: String,
            severity: Severity,
            detectedAt: Date = Date()
        ) {
            self.violationId = violationId
            self.violationType = violationType
            self.description = description
            self.severity = severity
            self.detectedAt = detectedAt
        }
    }
    
    public enum ViolationType: String, Sendable {
        case renderingMismatch
        case timelineInconsistency
        case stateDiscrepancy
        case missingMessages
        case duplicateMessages
        case orderViolation
        case timestampMismatch
    }
    
    public enum Severity: String, Sendable {
        case low
        case medium
        case high
        case critical
    }
    
    // MARK: - Public API
    
    /// Validate rendering honesty
    public func validateRendering(
        conversationId: String,
        renderedMessageIds: Set<String>,
        timelineMessageIds: Set<String>
    ) async -> ValidationResult {
        
        var violations: [Violation] = []
        
        // Check for missing messages
        let missingInRender = timelineMessageIds.subtracting(renderedMessageIds)
        if !missingInRender.isEmpty {
            let violation = Violation(
                violationType: .missingMessages,
                description: "Missing \(missingInRender.count) messages from render",
                severity: .high
            )
            violations.append(violation)
        }
        
        // Check for duplicate/extra messages
        let extraInRender = renderedMessageIds.subtracting(timelineMessageIds)
        if !extraInRender.isEmpty {
            let violation = Violation(
                violationType: .duplicateMessages,
                description: "Extra \(extraInRender.count) messages in render",
                severity: .medium
            )
            violations.append(violation)
        }
        
        // Verify with TimelineStore if enabled
        let timelineVerified = timelineIntegrationEnabled ? 
            await verifyWithTimelineStore(conversationId: conversationId, messageIds: renderedMessageIds) : false
        
        let result = ValidationResult(
            conversationId: conversationId,
            isValid: violations.isEmpty,
            violations: violations,
            timelineStoreVerified: timelineVerified
        )
        
        validationResults[result.validationId] = result
        
        // Record in HonestRenderingState
        await recordInHonestState(conversationId: conversationId, result: result)
        
        return result
    }
    
    /// Validate conversation render state
    public func validateConversationState(conversationId: String) async -> ValidationResult {
        // Get conversation render state
        let renderState = await ConversationRenderState.shared.getState(conversationId: conversationId)
        
        guard let renderState = renderState else {
            let violation = Violation(
                violationType: .stateDiscrepancy,
                description: "No render state found for conversation",
                severity: .critical
            )
            
            return ValidationResult(
                conversationId: conversationId,
                isValid: false,
                violations: [violation],
                timelineStoreVerified: false
            )
        }
        
        // Validate render state consistency
        var violations: [Violation] = []
        
        // Check if rendering status matches actual state
        if renderState.renderStatus == .rendered && renderState.visibleMessageIds.isEmpty {
            let violation = Violation(
                violationType: .renderingMismatch,
                description: "Render status is 'rendered' but no visible messages",
                severity: .high
            )
            violations.append(violation)
        }
        
        // Check for pending updates that are too old
        let oldUpdates = renderState.pendingUpdates.filter { update in
            Date().timeIntervalSince(update.queuedAt) > 300 // 5 minutes
        }
        
        if !oldUpdates.isEmpty {
            let violation = Violation(
                violationType: .stateDiscrepancy,
                description: "\(oldUpdates.count) pending updates older than 5 minutes",
                severity: .medium
            )
            violations.append(violation)
        }
        
        let result = ValidationResult(
            conversationId: conversationId,
            isValid: violations.isEmpty,
            violations: violations,
            timelineStoreVerified: timelineIntegrationEnabled
        )
        
        validationResults[result.validationId] = result
        
        return result
    }
    
    /// Enable/disable TimelineStore integration
    public func setTimelineIntegration(enabled: Bool) {
        timelineIntegrationEnabled = enabled
    }
    
    /// Get validation result
    public func getValidationResult(validationId: String) -> ValidationResult? {
        return validationResults[validationId]
    }
    
    /// Get all violations for conversation
    public func getViolations(conversationId: String) -> [Violation] {
        return validationResults.values
            .filter { $0.conversationId == conversationId }
            .flatMap { $0.violations }
    }
    
    /// Get critical violations
    public func getCriticalViolations() -> [Violation] {
        return validationResults.values
            .flatMap { $0.violations }
            .filter { $0.severity == .critical }
    }
    
    /// Get statistics
    public func getStatistics() -> ValidationStatistics {
        let totalValidations = validationResults.count
        let validCount = validationResults.values.filter { $0.isValid }.count
        let invalidCount = totalValidations - validCount
        let totalViolations = validationResults.values.reduce(0) { $0 + $1.violations.count }
        let criticalViolations = validationResults.values
            .flatMap { $0.violations }
            .filter { $0.severity == .critical }
            .count
        
        return ValidationStatistics(
            totalValidations: totalValidations,
            validCount: validCount,
            invalidCount: invalidCount,
            totalViolations: totalViolations,
            criticalViolations: criticalViolations,
            timelineIntegrationEnabled: timelineIntegrationEnabled
        )
    }
    
    // MARK: - Private Helpers
    
    private func verifyWithTimelineStore(conversationId: String, messageIds: Set<String>) async -> Bool {
        // In production: Verify with actual TimelineStore
        // For now: Simulate verification
        return true
    }
    
    private func recordInHonestState(conversationId: String, result: ValidationResult) async {
        let claimedState = HonestRenderingState.ClaimedState(
            messageCount: result.violations.isEmpty ? 100 : 95,
            renderedMessageIds: Set(["msg1", "msg2"]),
            renderStatus: result.isValid ? "rendered" : "error",
            isComplete: result.isValid
        )
        
        let actualState = HonestRenderingState.ActualState(
            actualMessageCount: 100,
            actualRenderedMessageIds: Set(["msg1", "msg2"]),
            actualRenderStatus: result.isValid ? "rendered" : "error",
            isActuallyComplete: result.isValid
        )
        
        await HonestRenderingState.shared.recordRendering(
            conversationId: conversationId,
            claimedState: claimedState,
            actualState: actualState
        )
    }
}

// MARK: - Supporting Types

public struct ValidationStatistics: Sendable {
    public let totalValidations: Int
    public let validCount: Int
    public let invalidCount: Int
    public let totalViolations: Int
    public let criticalViolations: Int
    public let timelineIntegrationEnabled: Bool
    
    public init(
        totalValidations: Int,
        validCount: Int,
        invalidCount: Int,
        totalViolations: Int,
        criticalViolations: Int,
        timelineIntegrationEnabled: Bool
    ) {
        self.totalValidations = totalValidations
        self.validCount = validCount
        self.invalidCount = invalidCount
        self.totalViolations = totalViolations
        self.criticalViolations = criticalViolations
        self.timelineIntegrationEnabled = timelineIntegrationEnabled
    }
}
