// FeatureChat/Data/DTOs/MessageEditDTO.swift
//
// Outbound: waangu-chat/modify-message
// {
//   "sessionId": "...",
//   "senderId": "...",
//   "conversationId": "...",
//   "codeMessage": "...",
//   "content": "{\"text\":\"...\"}",  // MessageContentDTO JSON string (same as send-message)
//   "status": "..."
// }
import Foundation

public struct OutboundModifyMessageDTO: Codable, Sendable, Equatable {
    public let sessionId: String
    public let senderId: String
    public let conversationId: String
    public let codeMessage: String
    public let content: String
    public let status: String

    public init(
        sessionId: String,
        senderId: String,
        conversationId: String,
        codeMessage: String,
        content: String,
        status: String
    ) {
        self.sessionId = sessionId
        self.senderId = senderId
        self.conversationId = conversationId
        self.codeMessage = codeMessage
        self.content = content
        self.status = status
    }
}

/// Legacy alias — prefer `OutboundModifyMessageDTO`.
public typealias OutboundMessageEditDTO = OutboundModifyMessageDTO

public struct InboundMessageEditDTO: Codable, Sendable {
    public let conversationId: String
    public let messageId: String
    public let userId: String
    public let newContent: MessageContentDTO
    public let editedAt: Double
}

/// Backend MESSAGE_MODIFIED payload received via MQTT / sync pull.
public struct BackendMessageModifiedDTO: Codable, Sendable {
    public let codeMessage: String
    public let conversationId: String
    public let senderId: String
    public let content: String
    public let previousContent: String?
    public let status: String?
    public let modifiedBy: String?
    public let modificationTimestamp: Double?
    public let previousContentHash: String?
    public let operationId: String?
    public let tenantId: String?
    public let country: String?
    public let modifiedAt: String?
    public let processingTimeMs: Double?
    public let checksum: String?
    public let eventType: String?
    public let eventVersion: Int?

    public var messageContent: MessageContentDTO {
        MessageContentWireCodec.decode(content, typeMessage: "TEXT")
    }

    public var resolvedEditedAt: Date? {
        if let raw = modificationTimestamp {
            let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
            return Date(timeIntervalSince1970: seconds)
        }
        guard let modifiedAt, !modifiedAt.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: modifiedAt) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: modifiedAt)
    }
}
