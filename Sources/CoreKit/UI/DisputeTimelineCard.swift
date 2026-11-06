//
//  DisputeTimelineCard.swift
//  CoreKit
//
//  Dispute timeline action card
//  Backend-driven dispute timeline UI
//

import Foundation

/// Dispute timeline action card
public struct DisputeTimelineCard: Sendable {
    public let cardId: String
    public let title: String
    public let disputeId: String
    public let status: DisputeStatus
    public let timeline: [TimelineEvent]
    public let transactionId: String
    public let amount: Decimal
    public let currency: String
    
    public init(cardId: String, title: String, disputeId: String, status: DisputeStatus, timeline: [TimelineEvent], transactionId: String, amount: Decimal, currency: String) {
        self.cardId = cardId
        self.title = title
        self.disputeId = disputeId
        self.status = status
        self.timeline = timeline
        self.transactionId = transactionId
        self.amount = amount
        self.currency = currency
    }
    
    public struct TimelineEvent: Sendable {
        public let eventId: String
        public let title: String
        public let description: String
        public let timestamp: Date
        public let actor: String
        
        public init(eventId: String, title: String, description: String, timestamp: Date, actor: String) {
            self.eventId = eventId
            self.title = title
            self.description = description
            self.timestamp = timestamp
            self.actor = actor
        }
    }
    
    public enum DisputeStatus: String, Sendable {
        case opened
        case underReview
        case evidenceRequired
        case resolved
        case closed
        case escalated
    }
}
