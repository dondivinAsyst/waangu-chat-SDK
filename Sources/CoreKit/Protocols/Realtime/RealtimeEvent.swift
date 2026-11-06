//
//  RealtimeEvent.swift
//  CoreKit
//
//  RULE: Realtime events ont sequence/correlation/source
//  Enhanced realtime event with sequence, correlation, and source tracking

import Foundation

/// Realtime event with full metadata
/// RULE: All realtime events must have sequence, correlation, and source
public struct RealtimeEvent: Sendable, Identifiable {
    public let id: String
    public let type: EventType
    public let sequenceNumber: Int64
    public let correlationId: String
    public let source: EventSource
    public let timestamp: Date
    public let payload: Data
    public let metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        type: EventType,
        sequenceNumber: Int64,
        correlationId: String,
        source: EventSource,
        timestamp: Date = Date(),
        payload: Data,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.sequenceNumber = sequenceNumber
        self.correlationId = correlationId
        self.source = source
        self.timestamp = timestamp
        self.payload = payload
        self.metadata = metadata
    }
}

public enum EventType: String, Sendable {
    case messageReceived = "MESSAGE_RECEIVED"
    case messageDelivered = "MESSAGE_DELIVERED"
    case messageSeen = "MESSAGE_SEEN"
    case messageDeleted = "MESSAGE_DELETED"
    case conversationUpdated = "CONVERSATION_UPDATED"
    case userTyping = "USER_TYPING"
    case userOnline = "USER_ONLINE"
    case userOffline = "USER_OFFLINE"
    case paymentReceived = "PAYMENT_RECEIVED"
    case paymentCompleted = "PAYMENT_COMPLETED"
    case systemNotification = "SYSTEM_NOTIFICATION"
}

public enum EventSource: String, Sendable {
    case backend = "BACKEND"
    case coreGateway = "Core"
    case compliance = "compliance"
    case projection = "projection"
    case identity = "Identity"
    case mqtt = "MQTT"
    case websocket = "WEBSOCKET"
}

/// Realtime event stream manager
/// RULE: Provides AsyncSequence for realtime events
public actor RealtimeEventStream {
    
    public static let shared = RealtimeEventStream()
    
    private var continuations: [UUID: AsyncStream<RealtimeEvent>.Continuation] = [:]
    private var eventHistory: [RealtimeEvent] = []
    private let maxHistorySize = 1000
    
    private init() {}
    
    /// Subscribe to realtime events
    /// RULE: Returns AsyncSequence of events with sequence/correlation/source
    public func subscribe() -> AsyncStream<RealtimeEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            Task {
                await self.registerContinuation(id: id, continuation: continuation)
            }
        }
    }
    
    private func registerContinuation(
        id: UUID,
        continuation: AsyncStream<RealtimeEvent>.Continuation
    ) {
        continuations[id] = continuation
        
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.unregisterContinuation(id: id)
            }
        }
    }
    
    private func unregisterContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
    
    /// Publishes event to all subscribers
    public func publish(_ event: RealtimeEvent) async {
        // Store in history
        eventHistory.append(event)
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst()
        }
        
        // Notify subscribers
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }
    
    public func getEventHistory() -> [RealtimeEvent] {
        return eventHistory
    }
    
    public func clearHistory() {
        eventHistory.removeAll()
    }
}
