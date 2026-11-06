//
//  RenderingStateReducer.swift
//  CoreKit
//
//  RULE: RenderingStateReducer actif
//  Reduces rendering state from backend events without local business logic

import Foundation

/// Rendering state reducer - transforms backend events into UI state
/// RULE: No local business logic, only state transformation
public actor RenderingStateReducer {
    
    public static let shared = RenderingStateReducer()
    
    private var currentState: RenderingState = .idle
    private var stateHistory: [StateTransition] = []
    private let maxHistorySize = 100
    
    private init() {}
    
    // MARK: - State Reduction
    
    /// Reduces backend event into new rendering state
    /// RULE: Pure state transformation, no business logic
    public func reduce(event: BackendEvent) async -> RenderingState {
        let previousState = currentState
        let newState = computeNewState(from: previousState, event: event)
        
        // Record transition
        let transition = StateTransition(
            from: previousState,
            to: newState,
            event: event,
            timestamp: Date()
        )
        
        stateHistory.append(transition)
        
        // Limit history size
        if stateHistory.count > maxHistorySize {
            stateHistory.removeFirst()
        }
        
        currentState = newState
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "operation": "state_reduced",
                "previous_state": previousState.description,
                "new_state": newState.description,
                "event_type": event.type.rawValue
            ]
        )
        
        return newState
    }
    
    /// Computes new state from event (pure function)
    /// RULE: No side effects, no business logic
    private func computeNewState(from state: RenderingState, event: BackendEvent) -> RenderingState {
        switch event.type {
        case .messageReceived:
            return .rendering(itemCount: state.itemCount + 1)
            
        case .messageDeleted:
            return .rendering(itemCount: max(0, state.itemCount - 1))
            
        case .conversationUpdated:
            return .rendering(itemCount: state.itemCount)
            
        case .syncStarted:
            return .syncing(progress: 0.0)
            
        case .syncProgress:
            if case .syncing = state {
                return .syncing(progress: event.metadata["progress"] as? Double ?? 0.0)
            }
            return state
            
        case .syncCompleted:
            return .rendering(itemCount: event.metadata["itemCount"] as? Int ?? state.itemCount)
            
        case .error:
            return .error(message: event.metadata["message"] as? String ?? "Unknown error")
            
        case .reset:
            return .idle
        }
    }
    
    // MARK: - State Access
    
    public func getCurrentState() -> RenderingState {
        return currentState
    }
    
    public func getStateHistory() -> [StateTransition] {
        return stateHistory
    }
    
    public func reset() {
        currentState = .idle
        stateHistory.removeAll()
    }
    
    // MARK: - Validation
    
    /// Validates state transition is valid
    public func validateTransition(from: RenderingState, to: RenderingState) -> Bool {
        // Define valid transitions
        switch (from, to) {
        case (.idle, .rendering), (.idle, .syncing):
            return true
        case (.rendering, .rendering), (.rendering, .syncing), (.rendering, .error):
            return true
        case (.syncing, .rendering), (.syncing, .error):
            return true
        case (.error, .rendering), (.error, .idle):
            return true
        default:
            return false
        }
    }
}

// MARK: - Types

public enum RenderingState: Sendable, Equatable {
    case idle
    case rendering(itemCount: Int)
    case syncing(progress: Double)
    case error(message: String)
    
    var itemCount: Int {
        switch self {
        case .rendering(let count):
            return count
        case .syncing, .idle, .error:
            return 0
        }
    }
    
    var description: String {
        switch self {
        case .idle:
            return "idle"
        case .rendering(let count):
            return "rendering(\(count))"
        case .syncing(let progress):
            return "syncing(\(progress))"
        case .error(let message):
            return "error(\(message))"
        }
    }
}

public struct BackendEvent: Sendable {
    public let type: EventType
    public let metadata: [String: Any]
    public let timestamp: Date
    
    public init(type: EventType, metadata: [String: Any] = [:], timestamp: Date = Date()) {
        self.type = type
        self.metadata = metadata
        self.timestamp = timestamp
    }
    
    public enum EventType: String, Sendable {
        case messageReceived
        case messageDeleted
        case conversationUpdated
        case syncStarted
        case syncProgress
        case syncCompleted
        case error
        case reset
    }
}

public struct StateTransition: Sendable {
    public let from: RenderingState
    public let to: RenderingState
    public let event: BackendEvent
    public let timestamp: Date
    
    public init(from: RenderingState, to: RenderingState, event: BackendEvent, timestamp: Date) {
        self.from = from
        self.to = to
        self.event = event
        self.timestamp = timestamp
    }
}
