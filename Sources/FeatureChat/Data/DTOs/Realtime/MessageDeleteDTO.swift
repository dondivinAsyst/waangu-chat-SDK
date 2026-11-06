// FeatureChat/Data/DTOs/MessageDeleteDTO.swift
import Foundation

// Topic IN: waangu-chat/delete-message
// {
//   "senderId": "...",
//   "conversationId": "...",
//   "codeMessage": "...",
//   "forEveryone": true
// }

public struct OutboundMessageDeleteDTO: Codable, Sendable {
    public let senderId: String
    public let conversationId: String
    public let codeMessage: String
    public let forEveryone: Bool

    public init(
        senderId: String,
        conversationId: String,
        codeMessage: String,
        forEveryone: Bool
    ) {
        self.senderId = senderId
        self.conversationId = conversationId
        self.codeMessage = codeMessage
        self.forEveryone = forEveryone
    }
}

public struct InboundMessageDeleteDTO: Codable, Sendable {
    public let senderId: String?
    public let conversationId: String?
    public let codeMessage: String?
    public let messageId: String?
    public let forEveryone: Bool?
    public let deletedBy: String?
    public let userId: String?
    public let scope: String?
    public let timestamp: Double?
    public let deletedAt: String?

    public var resolvedMessageId: String? {
        let code = codeMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !code.isEmpty { return code }
        let legacy = messageId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return legacy.isEmpty ? nil : legacy
    }

    public var resolvedForEveryone: Bool {
        if let forEveryone { return forEveryone }
        let normalized = scope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "everyone"
    }

    public var resolvedDeleterId: String? {
        let by = deletedBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !by.isEmpty { return by }
        let sender = senderId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return sender.isEmpty ? nil : sender
    }
}
