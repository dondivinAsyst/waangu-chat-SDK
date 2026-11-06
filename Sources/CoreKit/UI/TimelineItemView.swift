//
//  TimelineItemView.swift
//  CoreKit
//
//  RULE: Timeline SwiftUI/UIKit structurée
//  RULE: Tous les items passent par TimelineItemView
//  Unified timeline item architecture for all content types

import Foundation

/// Protocol for all timeline items
/// RULE: All timeline items must conform to this protocol
public protocol TimelineItemProtocol: Sendable, Identifiable {
    var id: String { get }
    var type: TimelineItemType { get }
    var timestamp: Date { get }
    var source: String { get }
    var metadata: [String: String] { get }
}

/// Timeline item type enumeration
public enum TimelineItemType: String, Sendable {
    case message = "MESSAGE"
    case payment = "PAYMENT"
    case qrCode = "QR_CODE"
    case merchant = "MERCHANT"
    case copilot = "COPILOT"
    case operator_ = "OPERATOR"
    case surface = "SURFACE"
    case notification = "NOTIFICATION"
    case systemEvent = "SYSTEM_EVENT"
}

/// Base timeline item implementation
public struct TimelineItem: TimelineItemProtocol {
    public let id: String
    public let type: TimelineItemType
    public let timestamp: Date
    public let source: String
    public let metadata: [String: String]
    public let content: TimelineContent
    
    public init(
        id: String = UUID().uuidString,
        type: TimelineItemType,
        timestamp: Date = Date(),
        source: String,
        metadata: [String: String] = [:],
        content: TimelineContent
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.source = source
        self.metadata = metadata
        self.content = content
    }
}

/// Timeline content union type
public enum TimelineContent: Sendable {
    case message(MessageContent)
    case payment(PaymentContent)
    case qrCode(QRCodeContent)
    case merchant(MerchantContent)
    case copilot(CopilotContent)
    case operator_(OperatorContent)
    case surface(SurfaceContent)
    case notification(NotificationContent)
    case systemEvent(SystemEventContent)
}

// MARK: - Content Types

public struct MessageContent: Sendable {
    public let messageId: String
    public let text: String
    public let senderId: String
    public let senderName: String
    
    public init(messageId: String, text: String, senderId: String, senderName: String) {
        self.messageId = messageId
        self.text = text
        self.senderId = senderId
        self.senderName = senderName
    }
}

public struct PaymentContent: Sendable {
    public let transactionId: String
    public let amount: Decimal
    public let currency: String
    public let recipientName: String
    public let status: String
    
    public init(transactionId: String, amount: Decimal, currency: String, recipientName: String, status: String) {
        self.transactionId = transactionId
        self.amount = amount
        self.currency = currency
        self.recipientName = recipientName
        self.status = status
    }
}

public struct QRCodeContent: Sendable {
    public let qrId: String
    public let qrData: String
    public let expiresAt: Date
    public let purpose: String
    
    public init(qrId: String, qrData: String, expiresAt: Date, purpose: String) {
        self.qrId = qrId
        self.qrData = qrData
        self.expiresAt = expiresAt
        self.purpose = purpose
    }
}

public struct MerchantContent: Sendable {
    public let merchantId: String
    public let merchantName: String
    public let action: String
    public let details: [String: String]
    
    public init(merchantId: String, merchantName: String, action: String, details: [String: String]) {
        self.merchantId = merchantId
        self.merchantName = merchantName
        self.action = action
        self.details = details
    }
}

public struct CopilotContent: Sendable {
    public let copilotId: String
    public let suggestion: String
    public let confidence: Double
    public let actions: [String]
    
    public init(copilotId: String, suggestion: String, confidence: Double, actions: [String]) {
        self.copilotId = copilotId
        self.suggestion = suggestion
        self.confidence = confidence
        self.actions = actions
    }
}

public struct OperatorContent: Sendable {
    public let operatorId: String
    public let operatorName: String
    public let message: String
    public let priority: String
    
    public init(operatorId: String, operatorName: String, message: String, priority: String) {
        self.operatorId = operatorId
        self.operatorName = operatorName
        self.message = message
        self.priority = priority
    }
}

public struct SurfaceContent: Sendable {
    public let surfaceId: String
    public let surfaceType: String
    public let title: String
    public let content: String
    
    public init(surfaceId: String, surfaceType: String, title: String, content: String) {
        self.surfaceId = surfaceId
        self.surfaceType = surfaceType
        self.title = title
        self.content = content
    }
}

public struct NotificationContent: Sendable {
    public let notificationId: String
    public let title: String
    public let body: String
    public let category: String
    
    public init(notificationId: String, title: String, body: String, category: String) {
        self.notificationId = notificationId
        self.title = title
        self.body = body
        self.category = category
    }
}

public struct SystemEventContent: Sendable {
    public let eventId: String
    public let eventType: String
    public let description: String
    
    public init(eventId: String, eventType: String, description: String) {
        self.eventId = eventId
        self.eventType = eventType
        self.description = description
    }
}

// MARK: - Timeline Item Manager

/// Manages timeline items
public actor TimelineItemManager {
    
    public static let shared = TimelineItemManager()
    
    private var items: [String: TimelineItem] = [:]
    
    private init() {}
    
    public func addItem(_ item: TimelineItem) {
        items[item.id] = item
    }
    
    public func getItem(id: String) -> TimelineItem? {
        return items[id]
    }
    
    public func getAllItems() -> [TimelineItem] {
        return Array(items.values).sorted { $0.timestamp > $1.timestamp }
    }
    
    public func getItems(ofType type: TimelineItemType) -> [TimelineItem] {
        return items.values.filter { $0.type == type }.sorted { $0.timestamp > $1.timestamp }
    }
    
    public func removeItem(id: String) {
        items.removeValue(forKey: id)
    }
    
    public func clear() {
        items.removeAll()
    }
}
