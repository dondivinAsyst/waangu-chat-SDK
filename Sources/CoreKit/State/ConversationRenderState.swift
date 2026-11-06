//
//  ConversationRenderState.swift
//  CoreKit
//
//  Centralized conversation rendering state
//  RULE: ConversationRenderState centralisé
//

import Foundation

/// Centralized conversation rendering state manager
/// Tracks what's being rendered, pending updates, and display state
public actor ConversationRenderState {
    
    public static let shared = ConversationRenderState()
    
    private var conversationStates: [String: ConversationState] = [:]
    private var renderQueue: [RenderOperation] = []
    
    private init() {}
    
    public struct ConversationState: Sendable {
        public let conversationId: String
        public var renderStatus: RenderStatus
        public var visibleMessageIds: Set<String>
        public var pendingUpdates: [PendingUpdate]
        public var lastRenderedAt: Date
        public var scrollPosition: ScrollPosition?
        public var isFullyLoaded: Bool
        
        public init(
            conversationId: String,
            renderStatus: RenderStatus = .idle,
            visibleMessageIds: Set<String> = [],
            pendingUpdates: [PendingUpdate] = [],
            lastRenderedAt: Date = Date(),
            scrollPosition: ScrollPosition? = nil,
            isFullyLoaded: Bool = false
        ) {
            self.conversationId = conversationId
            self.renderStatus = renderStatus
            self.visibleMessageIds = visibleMessageIds
            self.pendingUpdates = pendingUpdates
            self.lastRenderedAt = lastRenderedAt
            self.scrollPosition = scrollPosition
            self.isFullyLoaded = isFullyLoaded
        }
    }
    
    public enum RenderStatus: String, Sendable {
        case idle
        case rendering
        case rendered
        case updating
        case error
    }
    
    public struct PendingUpdate: Sendable {
        public let updateId: String
        public let messageId: String
        public let updateType: UpdateType
        public let queuedAt: Date
        
        public init(updateId: String, messageId: String, updateType: UpdateType, queuedAt: Date = Date()) {
            self.updateId = updateId
            self.messageId = messageId
            self.updateType = updateType
            self.queuedAt = queuedAt
        }
    }
    
    public enum UpdateType: String, Sendable {
        case newMessage
        case messageUpdate
        case messageDelete
        case statusUpdate
        case reactionUpdate
    }
    
    public struct ScrollPosition: Sendable {
        public let messageId: String
        public let offset: Double
        
        public init(messageId: String, offset: Double) {
            self.messageId = messageId
            self.offset = offset
        }
    }
    
    public struct RenderOperation: Sendable {
        public let operationId: String
        public let conversationId: String
        public let operationType: OperationType
        public let priority: Priority
        public let queuedAt: Date
        
        public init(
            operationId: String = UUID().uuidString,
            conversationId: String,
            operationType: OperationType,
            priority: Priority = .normal,
            queuedAt: Date = Date()
        ) {
            self.operationId = operationId
            self.conversationId = conversationId
            self.operationType = operationType
            self.priority = priority
            self.queuedAt = queuedAt
        }
    }
    
    public enum OperationType: String, Sendable {
        case initialRender
        case incrementalUpdate
        case fullRefresh
        case scrollUpdate
    }
    
    public enum Priority: Int, Sendable {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3
    }
    
    // MARK: - Public API
    
    /// Get conversation state
    public func getState(conversationId: String) -> ConversationState? {
        return conversationStates[conversationId]
    }
    
    /// Update conversation state
    public func updateState(conversationId: String, state: ConversationState) {
        conversationStates[conversationId] = state
    }
    
    /// Mark conversation as rendering
    public func markRendering(conversationId: String) {
        guard var state = conversationStates[conversationId] else {
            conversationStates[conversationId] = ConversationState(
                conversationId: conversationId,
                renderStatus: .rendering
            )
            return
        }
        
        state.renderStatus = .rendering
        conversationStates[conversationId] = state
    }
    
    /// Mark conversation as rendered
    public func markRendered(conversationId: String, visibleMessageIds: Set<String>) {
        guard var state = conversationStates[conversationId] else { return }
        
        state.renderStatus = .rendered
        state.visibleMessageIds = visibleMessageIds
        state.lastRenderedAt = Date()
        conversationStates[conversationId] = state
    }
    
    /// Add pending update
    public func addPendingUpdate(conversationId: String, update: PendingUpdate) {
        guard var state = conversationStates[conversationId] else {
            conversationStates[conversationId] = ConversationState(
                conversationId: conversationId,
                pendingUpdates: [update]
            )
            return
        }
        
        state.pendingUpdates.append(update)
        conversationStates[conversationId] = state
    }
    
    /// Clear pending updates
    public func clearPendingUpdates(conversationId: String) {
        guard var state = conversationStates[conversationId] else { return }
        
        state.pendingUpdates.removeAll()
        conversationStates[conversationId] = state
    }
    
    /// Update scroll position
    public func updateScrollPosition(conversationId: String, position: ScrollPosition) {
        guard var state = conversationStates[conversationId] else { return }
        
        state.scrollPosition = position
        conversationStates[conversationId] = state
    }
    
    /// Queue render operation
    public func queueRenderOperation(_ operation: RenderOperation) {
        renderQueue.append(operation)
        renderQueue.sort { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    /// Get next render operation
    public func dequeueRenderOperation() -> RenderOperation? {
        guard !renderQueue.isEmpty else { return nil }
        return renderQueue.removeFirst()
    }
    
    /// Get pending render operations
    public func getPendingOperations(conversationId: String) -> [RenderOperation] {
        return renderQueue.filter { $0.conversationId == conversationId }
    }
    
    /// Clear render queue
    public func clearRenderQueue(conversationId: String) {
        renderQueue.removeAll { $0.conversationId == conversationId }
    }
    
    /// Get statistics
    public func getStatistics() -> RenderStatistics {
        let totalConversations = conversationStates.count
        let renderingCount = conversationStates.values.filter { $0.renderStatus == .rendering }.count
        let renderedCount = conversationStates.values.filter { $0.renderStatus == .rendered }.count
        let totalPendingUpdates = conversationStates.values.reduce(0) { $0 + $1.pendingUpdates.count }
        let queuedOperations = renderQueue.count
        
        return RenderStatistics(
            totalConversations: totalConversations,
            renderingCount: renderingCount,
            renderedCount: renderedCount,
            totalPendingUpdates: totalPendingUpdates,
            queuedOperations: queuedOperations
        )
    }
}

// MARK: - Supporting Types

public struct RenderStatistics: Sendable {
    public let totalConversations: Int
    public let renderingCount: Int
    public let renderedCount: Int
    public let totalPendingUpdates: Int
    public let queuedOperations: Int
    
    public init(
        totalConversations: Int,
        renderingCount: Int,
        renderedCount: Int,
        totalPendingUpdates: Int,
        queuedOperations: Int
    ) {
        self.totalConversations = totalConversations
        self.renderingCount = renderingCount
        self.renderedCount = renderedCount
        self.totalPendingUpdates = totalPendingUpdates
        self.queuedOperations = queuedOperations
    }
}
