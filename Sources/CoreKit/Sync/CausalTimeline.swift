//
//  CausalTimeline.swift
//  CoreKit
//
//  Causally ordered timeline for distributed events
//  RULE: Timeline causalement ordonnée

import Foundation

public actor CausalTimeline {
    
    public static let shared = CausalTimeline()
    
    private var events: [CausalEvent] = []
    private var vectorClock: VectorClock = VectorClock()
    private var deviceId: String
    
    private init() {
        self.deviceId = UUID().uuidString
    }
    
    // MARK: - Event Recording
    
    /// Records an event with causal ordering
    /// RULE: Timeline causalement ordonnée
    public func recordEvent(
        action: String,
        metadata: [String: String] = [:]
    ) async -> CausalEvent {
        
        // Increment vector clock for this device
        vectorClock.increment(deviceId: deviceId)
        
        let event = CausalEvent(
            id: UUID().uuidString,
            deviceId: deviceId,
            action: action,
            metadata: metadata,
            vectorClock: vectorClock.copy(),
            timestamp: Date()
        )
        
        events.append(event)
        
        // Sort events by causal order
        events.sort { $0.happensBefore($1) }
        
        return event
    }
    
    /// Merges remote event into timeline
    public func mergeRemoteEvent(_ event: CausalEvent) async throws {
        
        // Update vector clock
        vectorClock.merge(event.vectorClock)
        
        // Check for causal violations
        try validateCausalConsistency(event)
        
        // Insert event in causal order
        events.append(event)
        events.sort { $0.happensBefore($1) }
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "action": "causal_event_merged",
                "event_id": event.id,
                "device_id": event.deviceId
            ],
            severity: .info
        )
    }
    
    // MARK: - Causal Consistency
    
    private func validateCausalConsistency(_ event: CausalEvent) throws {
        // Check if we have all causal dependencies
        for (deviceId, clock) in event.vectorClock.clocks {
            if deviceId != event.deviceId {
                let ourClock = vectorClock.clocks[deviceId] ?? 0
                if clock > ourClock + 1 {
                    throw CausalError.missingCausalDependency(
                        deviceId: deviceId,
                        expected: ourClock + 1,
                        received: clock
                    )
                }
            }
        }
    }
    
    /// Checks if event A happens before event B
    public func happensBefore(eventA: CausalEvent, eventB: CausalEvent) -> Bool {
        eventA.happensBefore(eventB)
    }
    
    /// Gets causally ordered events
    public func getOrderedEvents() -> [CausalEvent] {
        events
    }
    
    /// Gets events after a specific vector clock
    public func getEventsSince(vectorClock: VectorClock) -> [CausalEvent] {
        events.filter { event in
            !event.vectorClock.happensBefore(vectorClock)
        }
    }
    
    // MARK: - Types
    
    public struct CausalEvent: Codable {
        public let id: String
        public let deviceId: String
        public let action: String
        public let metadata: [String: String]
        public let vectorClock: VectorClock
        public let timestamp: Date
        
        /// Determines if this event happens before another
        public func happensBefore(_ other: CausalEvent) -> Bool {
            vectorClock.happensBefore(other.vectorClock)
        }
        
        /// Determines if events are concurrent
        public func isConcurrentWith(_ other: CausalEvent) -> Bool {
            !happensBefore(other) && !other.happensBefore(self)
        }
    }
    
    public struct VectorClock: Codable {
        public var clocks: [String: Int] = [:]
        
        public mutating func increment(deviceId: String) {
            clocks[deviceId, default: 0] += 1
        }
        
        public mutating func merge(_ other: VectorClock) {
            for (deviceId, clock) in other.clocks {
                clocks[deviceId] = max(clocks[deviceId] ?? 0, clock)
            }
        }
        
        public func happensBefore(_ other: VectorClock) -> Bool {
            var hasLess = false
            
            for (deviceId, clock) in clocks {
                let otherClock = other.clocks[deviceId] ?? 0
                if clock > otherClock {
                    return false
                }
                if clock < otherClock {
                    hasLess = true
                }
            }
            
            for (deviceId, otherClock) in other.clocks {
                if clocks[deviceId] == nil && otherClock > 0 {
                    hasLess = true
                }
            }
            
            return hasLess
        }
        
        public func copy() -> VectorClock {
            VectorClock(clocks: clocks)
        }
    }
    
    public enum CausalError: Error, LocalizedError {
        case missingCausalDependency(deviceId: String, expected: Int, received: Int)
        
        public var errorDescription: String? {
            switch self {
            case .missingCausalDependency(let deviceId, let expected, let received):
                return "Missing causal dependency for device \(deviceId): expected \(expected), received \(received)"
            }
        }
    }
}
