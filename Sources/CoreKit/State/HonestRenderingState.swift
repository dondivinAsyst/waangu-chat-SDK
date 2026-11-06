//
//  HonestRenderingState.swift
//  CoreKit
//
//  Honest rendering state tracking
//  RULE: HonestRenderingState centralisé
//  Tracks what's actually rendered vs what's claimed
//

import Foundation

/// Honest rendering state manager
/// Ensures rendering claims match reality
public actor HonestRenderingState {
    
    public static let shared = HonestRenderingState()
    
    private var renderingRecords: [String: RenderingRecord] = [:]
    private var discrepancies: [RenderingDiscrepancy] = []
    
    private init() {}
    
    public struct RenderingRecord: Sendable {
        public let recordId: String
        public let conversationId: String
        public let claimedState: ClaimedState
        public let actualState: ActualState
        public let timestamp: Date
        public let isHonest: Bool
        
        public init(
            recordId: String = UUID().uuidString,
            conversationId: String,
            claimedState: ClaimedState,
            actualState: ActualState,
            timestamp: Date = Date()
        ) {
            self.recordId = recordId
            self.conversationId = conversationId
            self.claimedState = claimedState
            self.actualState = actualState
            self.timestamp = timestamp
            self.isHonest = claimedState.matches(actualState)
        }
    }
    
    public struct ClaimedState: Sendable {
        public let messageCount: Int
        public let renderedMessageIds: Set<String>
        public let renderStatus: String
        public let isComplete: Bool
        
        public init(
            messageCount: Int,
            renderedMessageIds: Set<String>,
            renderStatus: String,
            isComplete: Bool
        ) {
            self.messageCount = messageCount
            self.renderedMessageIds = renderedMessageIds
            self.renderStatus = renderStatus
            self.isComplete = isComplete
        }
        
        public func matches(_ actual: ActualState) -> Bool {
            return messageCount == actual.actualMessageCount &&
                   renderedMessageIds == actual.actualRenderedMessageIds &&
                   isComplete == actual.isActuallyComplete
        }
    }
    
    public struct ActualState: Sendable {
        public let actualMessageCount: Int
        public let actualRenderedMessageIds: Set<String>
        public let actualRenderStatus: String
        public let isActuallyComplete: Bool
        public let verifiedAt: Date
        
        public init(
            actualMessageCount: Int,
            actualRenderedMessageIds: Set<String>,
            actualRenderStatus: String,
            isActuallyComplete: Bool,
            verifiedAt: Date = Date()
        ) {
            self.actualMessageCount = actualMessageCount
            self.actualRenderedMessageIds = actualRenderedMessageIds
            self.actualRenderStatus = actualRenderStatus
            self.isActuallyComplete = isActuallyComplete
            self.verifiedAt = verifiedAt
        }
    }
    
    public struct RenderingDiscrepancy: Sendable {
        public let discrepancyId: String
        public let conversationId: String
        public let discrepancyType: DiscrepancyType
        public let claimedValue: String
        public let actualValue: String
        public let detectedAt: Date
        public let severity: Severity
        
        public init(
            discrepancyId: String = UUID().uuidString,
            conversationId: String,
            discrepancyType: DiscrepancyType,
            claimedValue: String,
            actualValue: String,
            detectedAt: Date = Date(),
            severity: Severity = .medium
        ) {
            self.discrepancyId = discrepancyId
            self.conversationId = conversationId
            self.discrepancyType = discrepancyType
            self.claimedValue = claimedValue
            self.actualValue = actualValue
            self.detectedAt = detectedAt
            self.severity = severity
        }
    }
    
    public enum DiscrepancyType: String, Sendable {
        case messageCountMismatch
        case renderedIdsMismatch
        case statusMismatch
        case completionMismatch
        case visibilityMismatch
    }
    
    public enum Severity: String, Sendable {
        case low
        case medium
        case high
        case critical
    }
    
    // MARK: - Public API
    
    /// Record rendering state
    public func recordRendering(
        conversationId: String,
        claimedState: ClaimedState,
        actualState: ActualState
    ) {
        let record = RenderingRecord(
            conversationId: conversationId,
            claimedState: claimedState,
            actualState: actualState
        )
        
        renderingRecords[record.recordId] = record
        
        // Detect discrepancies
        if !record.isHonest {
            detectDiscrepancies(record: record)
        }
    }
    
    /// Verify rendering honesty
    public func verifyHonesty(conversationId: String) -> HonestyVerification {
        let records = renderingRecords.values.filter { $0.conversationId == conversationId }
        
        guard !records.isEmpty else {
            return HonestyVerification(
                conversationId: conversationId,
                isHonest: true,
                totalRecords: 0,
                honestRecords: 0,
                dishonestRecords: 0,
                discrepancies: []
            )
        }
        
        let honestCount = records.filter { $0.isHonest }.count
        let dishonestCount = records.count - honestCount
        let conversationDiscrepancies = discrepancies.filter { $0.conversationId == conversationId }
        
        return HonestyVerification(
            conversationId: conversationId,
            isHonest: dishonestCount == 0,
            totalRecords: records.count,
            honestRecords: honestCount,
            dishonestRecords: dishonestCount,
            discrepancies: conversationDiscrepancies
        )
    }
    
    /// Get all discrepancies
    public func getDiscrepancies(conversationId: String? = nil) -> [RenderingDiscrepancy] {
        if let conversationId = conversationId {
            return discrepancies.filter { $0.conversationId == conversationId }
        }
        return discrepancies
    }
    
    /// Get critical discrepancies
    public func getCriticalDiscrepancies() -> [RenderingDiscrepancy] {
        return discrepancies.filter { $0.severity == .critical }
    }
    
    /// Clear discrepancies
    public func clearDiscrepancies(conversationId: String) {
        discrepancies.removeAll { $0.conversationId == conversationId }
    }
    
    /// Get statistics
    public func getStatistics() -> HonestyStatistics {
        let totalRecords = renderingRecords.count
        let honestRecords = renderingRecords.values.filter { $0.isHonest }.count
        let dishonestRecords = totalRecords - honestRecords
        let totalDiscrepancies = discrepancies.count
        let criticalDiscrepancies = discrepancies.filter { $0.severity == .critical }.count
        
        let honestyRate = totalRecords > 0 ? Double(honestRecords) / Double(totalRecords) : 1.0
        
        return HonestyStatistics(
            totalRecords: totalRecords,
            honestRecords: honestRecords,
            dishonestRecords: dishonestRecords,
            totalDiscrepancies: totalDiscrepancies,
            criticalDiscrepancies: criticalDiscrepancies,
            honestyRate: honestyRate
        )
    }
    
    // MARK: - Private Helpers
    
    private func detectDiscrepancies(record: RenderingRecord) {
        // Message count mismatch
        if record.claimedState.messageCount != record.actualState.actualMessageCount {
            let discrepancy = RenderingDiscrepancy(
                conversationId: record.conversationId,
                discrepancyType: .messageCountMismatch,
                claimedValue: "\(record.claimedState.messageCount)",
                actualValue: "\(record.actualState.actualMessageCount)",
                severity: .high
            )
            discrepancies.append(discrepancy)
        }
        
        // Rendered IDs mismatch
        if record.claimedState.renderedMessageIds != record.actualState.actualRenderedMessageIds {
            let discrepancy = RenderingDiscrepancy(
                conversationId: record.conversationId,
                discrepancyType: .renderedIdsMismatch,
                claimedValue: "\(record.claimedState.renderedMessageIds.count) IDs",
                actualValue: "\(record.actualState.actualRenderedMessageIds.count) IDs",
                severity: .medium
            )
            discrepancies.append(discrepancy)
        }
        
        // Completion mismatch
        if record.claimedState.isComplete != record.actualState.isActuallyComplete {
            let discrepancy = RenderingDiscrepancy(
                conversationId: record.conversationId,
                discrepancyType: .completionMismatch,
                claimedValue: "\(record.claimedState.isComplete)",
                actualValue: "\(record.actualState.isActuallyComplete)",
                severity: .critical
            )
            discrepancies.append(discrepancy)
        }
    }
}

// MARK: - Supporting Types

public struct HonestyVerification: Sendable {
    public let conversationId: String
    public let isHonest: Bool
    public let totalRecords: Int
    public let honestRecords: Int
    public let dishonestRecords: Int
    public let discrepancies: [HonestRenderingState.RenderingDiscrepancy]
    
    public init(
        conversationId: String,
        isHonest: Bool,
        totalRecords: Int,
        honestRecords: Int,
        dishonestRecords: Int,
        discrepancies: [HonestRenderingState.RenderingDiscrepancy]
    ) {
        self.conversationId = conversationId
        self.isHonest = isHonest
        self.totalRecords = totalRecords
        self.honestRecords = honestRecords
        self.dishonestRecords = dishonestRecords
        self.discrepancies = discrepancies
    }
}

public struct HonestyStatistics: Sendable {
    public let totalRecords: Int
    public let honestRecords: Int
    public let dishonestRecords: Int
    public let totalDiscrepancies: Int
    public let criticalDiscrepancies: Int
    public let honestyRate: Double
    
    public init(
        totalRecords: Int,
        honestRecords: Int,
        dishonestRecords: Int,
        totalDiscrepancies: Int,
        criticalDiscrepancies: Int,
        honestyRate: Double
    ) {
        self.totalRecords = totalRecords
        self.honestRecords = honestRecords
        self.dishonestRecords = dishonestRecords
        self.totalDiscrepancies = totalDiscrepancies
        self.criticalDiscrepancies = criticalDiscrepancies
        self.honestyRate = honestyRate
    }
}
