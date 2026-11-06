//
//  AIForensics.swift
//  CoreKit
//
//  Forensic tracking for AI operations
//  RULE: IA forensicable

import Foundation
import WaanguCoreKit

public actor AIForensics {
    
    public static let shared = AIForensics()
    
    private var aiOperations: [AIOperation] = []
    private var promptHistory: [PromptRecord] = []
    private var responseHistory: [ResponseRecord] = []
    
    private init() {}
    
    // MARK: - AI Operation Tracking
    
    /// Records AI operation for forensics
    /// RULE: IA forensicable
    public func recordAIOperation(
        operationType: AIOperationType,
        input: String,
        output: String,
        model: String,
        userId: String?,
        metadata: [String: String] = [:]
    ) async -> String {
        
        let operationId = UUID().uuidString
        
        let operation = AIOperation(
            id: operationId,
            type: operationType,
            input: input,
            output: output,
            model: model,
            userId: userId,
            metadata: metadata,
            timestamp: Date()
        )
        
        aiOperations.append(operation)
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "action": "ai_operation_recorded",
                "operation_id": operationId,
                "type": operationType.rawValue,
                "model": model,
                "user_id": userId ?? "anonymous"
            ],
            severity: .info
        )
        
        return operationId
    }
    
    /// Records prompt for forensics
    public func recordPrompt(
        prompt: String,
        userId: String?,
        context: [String: String] = [:]
    ) async -> String {
        
        let promptId = UUID().uuidString
        
        let record = PromptRecord(
            id: promptId,
            prompt: prompt,
            userId: userId,
            context: context,
            timestamp: Date()
        )
        
        promptHistory.append(record)
        
        return promptId
    }
    
    /// Records AI response for forensics
    public func recordResponse(
        promptId: String,
        response: String,
        model: String,
        tokensUsed: Int,
        latencyMs: Int
    ) async {
        
        let record = ResponseRecord(
            id: UUID().uuidString,
            promptId: promptId,
            response: response,
            model: model,
            tokensUsed: tokensUsed,
            latencyMs: latencyMs,
            timestamp: Date()
        )
        
        responseHistory.append(record)
    }
    
    // MARK: - Forensic Queries
    
    /// Gets AI operations for user
    public func getOperationsForUser(_ userId: String) -> [AIOperation] {
        aiOperations.filter { $0.userId == userId }
    }
    
    /// Gets AI operation by ID
    public func getOperation(_ operationId: String) -> AIOperation? {
        aiOperations.first { $0.id == operationId }
    }
    
    /// Gets prompt history for user
    public func getPromptHistory(userId: String, limit: Int = 100) -> [PromptRecord] {
        Array(promptHistory.filter { $0.userId == userId }.prefix(limit))
    }
    
    /// Gets response for prompt
    public func getResponse(promptId: String) -> ResponseRecord? {
        responseHistory.first { $0.promptId == promptId }
    }
    
    /// Generates forensic report for AI operations
    public func generateForensicReport(
        userId: String?,
        startDate: Date,
        endDate: Date
    ) -> AIForensicReport {
        
        let filteredOps = aiOperations.filter { operation in
            let matchesUser = userId == nil || operation.userId == userId
            let inDateRange = operation.timestamp >= startDate && operation.timestamp <= endDate
            return matchesUser && inDateRange
        }
        
        let totalOperations = filteredOps.count
        let operationsByType = Dictionary(grouping: filteredOps) { $0.type }
        let modelUsage = Dictionary(grouping: filteredOps) { $0.model }
        
        return AIForensicReport(
            userId: userId,
            startDate: startDate,
            endDate: endDate,
            totalOperations: totalOperations,
            operationsByType: operationsByType.mapValues { $0.count },
            modelUsage: modelUsage.mapValues { $0.count },
            operations: filteredOps,
            generatedAt: Date()
        )
    }
    
    // MARK: - Cleanup
    
    public func cleanupOldRecords(olderThan: TimeInterval = 2592000) async { // 30 days
        let cutoff = Date().addingTimeInterval(-olderThan)
        
        aiOperations = aiOperations.filter { $0.timestamp > cutoff }
        promptHistory = promptHistory.filter { $0.timestamp > cutoff }
        responseHistory = responseHistory.filter { $0.timestamp > cutoff }
    }
    
    // MARK: - Types
    
    public struct AIOperation {
        public let id: String
        public let type: AIOperationType
        public let input: String
        public let output: String
        public let model: String
        public let userId: String?
        public let metadata: [String: String]
        public let timestamp: Date
    }
    
    public struct PromptRecord {
        public let id: String
        public let prompt: String
        public let userId: String?
        public let context: [String: String]
        public let timestamp: Date
    }
    
    public struct ResponseRecord {
        public let id: String
        public let promptId: String
        public let response: String
        public let model: String
        public let tokensUsed: Int
        public let latencyMs: Int
        public let timestamp: Date
    }
    
    public struct AIForensicReport {
        public let userId: String?
        public let startDate: Date
        public let endDate: Date
        public let totalOperations: Int
        public let operationsByType: [AIOperationType: Int]
        public let modelUsage: [String: Int]
        public let operations: [AIOperation]
        public let generatedAt: Date
    }
    
    public enum AIOperationType: String, Codable {
        case translation
        case summarization
        case chatCompletion
        case codeGeneration
        case imageGeneration
        case textToSpeech
        case speechToText
        case moderation
        case embedding
    }
}
