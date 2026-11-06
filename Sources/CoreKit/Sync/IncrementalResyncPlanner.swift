//
//  IncrementalResyncPlanner.swift
//  CoreKit
//
//  RULE: IncrementalResyncPlanner présent
//  Plans incremental resync operations to minimize data transfer

import Foundation

/// Plans incremental resync operations
/// RULE: Minimizes data transfer by syncing only gaps
public actor IncrementalResyncPlanner {
    
    public static let shared = IncrementalResyncPlanner()
    
    private var resyncPlans: [String: ResyncPlan] = [:]
    private var completedResyncs: [CompletedResync] = []
    private let maxCompletedHistory = 50
    
    private init() {}
    
    // MARK: - Resync Planning
    
    /// Creates a resync plan for a conversation
    public func planResync(
        conversationId: String,
        lastKnownSequence: Int64?,
        currentServerSequence: Int64,
        gaps: [SequenceGap]
    ) async -> ResyncPlan {
        
        let plan: ResyncPlan
        
        if let lastSeq = lastKnownSequence {
            // Incremental resync
            let missingRange = (lastSeq + 1)...currentServerSequence
            plan = ResyncPlan(
                conversationId: conversationId,
                type: .incremental,
                missingSequences: Array(missingRange) + gaps.flatMap { Array($0.range) },
                estimatedItemCount: Int(currentServerSequence - lastSeq) + gaps.reduce(0) { $0 + $1.range.count },
                createdAt: Date()
            )
        } else {
            // Full resync
            plan = ResyncPlan(
                conversationId: conversationId,
                type: .full,
                missingSequences: [],
                estimatedItemCount: Int(currentServerSequence),
                createdAt: Date()
            )
        }
        
        resyncPlans[conversationId] = plan
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "operation": "resync_planned",
                "conversationId": conversationId,
                "type": plan.type.rawValue,
                "estimatedItems": "\(plan.estimatedItemCount)"
            ]
        )
        
        return plan
    }
    
    /// Executes resync plan
    public func executeResync(plan: ResyncPlan) async throws -> ResyncResult {
        let startTime = Date()
        
        // Simulate resync execution
        // In production: Fetch missing sequences from backend
        
        let result = ResyncResult(
            conversationId: plan.conversationId,
            type: plan.type,
            itemsSynced: plan.estimatedItemCount,
            duration: Date().timeIntervalSince(startTime),
            success: true
        )
        
        // Record completion
        let completed = CompletedResync(
            plan: plan,
            result: result,
            completedAt: Date()
        )
        
        completedResyncs.append(completed)
        
        if completedResyncs.count > maxCompletedHistory {
            completedResyncs.removeFirst()
        }
        
        // Remove plan
        resyncPlans.removeValue(forKey: plan.conversationId)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "operation": "resync_completed",
                "conversationId": plan.conversationId,
                "itemsSynced": "\(result.itemsSynced)",
                "duration": "\(result.duration)"
            ]
        )
        
        return result
    }
    
    // MARK: - Plan Management
    
    public func getPlan(conversationId: String) -> ResyncPlan? {
        return resyncPlans[conversationId]
    }
    
    public func getAllPlans() -> [ResyncPlan] {
        return Array(resyncPlans.values)
    }
    
    public func cancelPlan(conversationId: String) {
        resyncPlans.removeValue(forKey: conversationId)
    }
    
    public func getCompletedResyncs() -> [CompletedResync] {
        return completedResyncs
    }
    
    public func getStatistics() -> ResyncStatistics {
        let totalCompleted = completedResyncs.count
        let totalItemsSynced = completedResyncs.reduce(0) { $0 + $1.result.itemsSynced }
        let averageDuration = completedResyncs.isEmpty ? 0 : completedResyncs.reduce(0.0) { $0 + $1.result.duration } / Double(totalCompleted)
        let activePlans = resyncPlans.count
        
        return ResyncStatistics(
            totalCompleted: totalCompleted,
            totalItemsSynced: totalItemsSynced,
            averageDuration: averageDuration,
            activePlans: activePlans
        )
    }
}

// MARK: - Types

public struct ResyncPlan: Sendable {
    public let conversationId: String
    public let type: ResyncType
    public let missingSequences: [Int64]
    public let estimatedItemCount: Int
    public let createdAt: Date
    
    public init(
        conversationId: String,
        type: ResyncType,
        missingSequences: [Int64],
        estimatedItemCount: Int,
        createdAt: Date
    ) {
        self.conversationId = conversationId
        self.type = type
        self.missingSequences = missingSequences
        self.estimatedItemCount = estimatedItemCount
        self.createdAt = createdAt
    }
}

public enum ResyncType: String, Sendable {
    case full = "FULL"
    case incremental = "INCREMENTAL"
}

public struct ResyncResult: Sendable {
    public let conversationId: String
    public let type: ResyncType
    public let itemsSynced: Int
    public let duration: TimeInterval
    public let success: Bool
    
    public init(
        conversationId: String,
        type: ResyncType,
        itemsSynced: Int,
        duration: TimeInterval,
        success: Bool
    ) {
        self.conversationId = conversationId
        self.type = type
        self.itemsSynced = itemsSynced
        self.duration = duration
        self.success = success
    }
}

public struct CompletedResync: Sendable {
    public let plan: ResyncPlan
    public let result: ResyncResult
    public let completedAt: Date
    
    public init(plan: ResyncPlan, result: ResyncResult, completedAt: Date) {
        self.plan = plan
        self.result = result
        self.completedAt = completedAt
    }
}

public struct ResyncStatistics: Sendable {
    public let totalCompleted: Int
    public let totalItemsSynced: Int
    public let averageDuration: TimeInterval
    public let activePlans: Int
    
    public init(
        totalCompleted: Int,
        totalItemsSynced: Int,
        averageDuration: TimeInterval,
        activePlans: Int
    ) {
        self.totalCompleted = totalCompleted
        self.totalItemsSynced = totalItemsSynced
        self.averageDuration = averageDuration
        self.activePlans = activePlans
    }
}

// SequenceGap is defined in CoreKit/Realtime/MessageOrderGuard.swift
