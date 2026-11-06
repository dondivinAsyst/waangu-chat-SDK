// FeatureChat/Data/DTOs/DeliveryReceiptDTO.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: OutboundMarkDeliveredDTO
// ─────────────────────────────────────────────────────────────
// Published to `waangu-chat/mark-delivered` when the client receives
// a message from another user.

public struct OutboundMarkDeliveredDTO: Codable, Sendable, Equatable {

    public let codeMessage: String
    public let conversationId: String
    public let userId: String
    public let deliveredAt: Int64?

    public init(
        codeMessage: String,
        conversationId: String,
        userId: String,
        deliveredAt: Int64? = nil
    ) {
        self.codeMessage = codeMessage
        self.conversationId = conversationId
        self.userId = userId
        self.deliveredAt = deliveredAt
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: OutboundMarkAsReadDTO
// ─────────────────────────────────────────────────────────────
// Published to `waangu-chat/mark-as-read` when the user opens/views
// an incoming message.

public struct OutboundMarkAsReadDTO: Codable, Sendable, Equatable {

    public let codeMessage: String
    public let userId: String

    public init(codeMessage: String, userId: String) {
        self.codeMessage = codeMessage
        self.userId = userId
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: InboundDeliveryReceiptDTO
// ─────────────────────────────────────────────────────────────
// Backend `MESSAGE_DELIVERED` payload (nested under `payload`).
//
// Example:
// {
//   "codeMessage": "...",
//   "conversationId": "...",
//   "userId": "<who delivered>",
//   "senderId": "<message author>",
//   "deliveredAt": 1784217472448,
//   "deliveredTimestamp": "2026-07-16T15:57:52.448Z",
//   "deviceType": null,
//   "eventType": "MESSAGE_DELIVERED",
//   "eventVersion": 1
// }

public struct InboundDeliveryReceiptDTO: Codable, Sendable, Equatable {

    public let codeMessage: String
    public let conversationId: String
    public let userId: String
    public let senderId: String?
    public let deliveredAt: Int64?
    public let deliveredTimestamp: String?
    public let deviceType: String?
    public let eventType: String?
    public let eventVersion: Int?

    public init(
        codeMessage: String,
        conversationId: String,
        userId: String,
        senderId: String? = nil,
        deliveredAt: Int64? = nil,
        deliveredTimestamp: String? = nil,
        deviceType: String? = nil,
        eventType: String? = nil,
        eventVersion: Int? = nil
    ) {
        self.codeMessage = codeMessage
        self.conversationId = conversationId
        self.userId = userId
        self.senderId = senderId
        self.deliveredAt = deliveredAt
        self.deliveredTimestamp = deliveredTimestamp
        self.deviceType = deviceType
        self.eventType = eventType
        self.eventVersion = eventVersion
    }

    /// Prefer epoch millis, then ISO string.
    public var deliveredDate: Date? {
        if let deliveredAt {
            let seconds = deliveredAt > 10_000_000_000
                ? TimeInterval(deliveredAt) / 1_000
                : TimeInterval(deliveredAt)
            return Date(timeIntervalSince1970: seconds)
        }
        guard let deliveredTimestamp, !deliveredTimestamp.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: deliveredTimestamp) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: deliveredTimestamp)
    }
}
