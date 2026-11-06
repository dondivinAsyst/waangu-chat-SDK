// FeatureChat/Data/DTOs/ReactionDTO.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: OutboundReactMessageDTO
// ─────────────────────────────────────────────────────────────
// Published to `waangu-chat/react-message` (add / change emoji).
// Published to `waangu-chat/remove-reaction` with `OutboundRemoveReactionDTO` only.

public struct OutboundReactMessageDTO: Codable, Sendable, Equatable {
    public let sessionId: String
    public let userId: String
    public let conversationId: String
    public let codeMessage: String
    public let reaction: String

    public init(
        sessionId: String,
        userId: String,
        conversationId: String,
        codeMessage: String,
        reaction: String
    ) {
        self.sessionId = sessionId
        self.userId = userId
        self.conversationId = conversationId
        self.codeMessage = codeMessage
        self.reaction = reaction
    }
}

/// Published to `waangu-chat/remove-reaction` — no emoji field.
public struct OutboundRemoveReactionDTO: Codable, Sendable, Equatable {
    public let sessionId: String
    public let userId: String
    public let conversationId: String
    public let codeMessage: String

    public init(
        sessionId: String,
        userId: String,
        conversationId: String,
        codeMessage: String
    ) {
        self.sessionId = sessionId
        self.userId = userId
        self.conversationId = conversationId
        self.codeMessage = codeMessage
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Reactor identity
// ─────────────────────────────────────────────────────────────

/// Resolves who actually reacted when backends disagree on `userId` vs `senderId`.
///
/// Contract preference: `userId` is the reactor.
/// Ambiguity fix: when the two IDs differ, prefer the one that is **not** the message author
/// so peer reactions on *your* sent messages are not stored under your userId (overwrite).
enum MessageReactionIdentity {
    static func resolveReactor(
        userId: String?,
        senderId: String?,
        messageAuthorId: String?
    ) -> String {
        let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sid = senderId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = messageAuthorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !uid.isEmpty, !sid.isEmpty, uid != sid, !author.isEmpty {
            if uid == author, sid != author { return sid }
            if sid == author, uid != author { return uid }
        }

        if !uid.isEmpty { return uid }
        return sid
    }
}

/// Inbound `MESSAGE_REACTION_ADDED` / `MESSAGE_REACTION_REMOVED` MQTT payload.
/// Fields are optional so null / alternate key names (`emoji`, `messageId`) still decode.
public struct BackendMessageReactionEventDTO: Codable, Sendable {
    public let codeMessage: String?
    public let messageId: String?
    public let conversationId: String?
    public let userId: String?
    public let senderId: String?
    public let reaction: String?
    public let emoji: String?
    public let reactedAt: String?
    public let operationId: String?
    public let tenantId: String?
    public let country: String?
    public let eventType: String?
    public let eventVersion: Int?

    public var resolvedCodeMessage: String {
        let code = codeMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !code.isEmpty { return code }
        return messageId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public func resolvedReactorId(messageAuthorId: String?) -> String {
        MessageReactionIdentity.resolveReactor(
            userId: userId,
            senderId: senderId,
            messageAuthorId: messageAuthorId
        )
    }

    public var resolvedReaction: String {
        let value = reaction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !value.isEmpty { return value }
        return emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var resolvedReactedAt: Date? {
        guard let reactedAt, !reactedAt.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: reactedAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: reactedAt)
    }

    public var isRemovalEvent: Bool {
        eventType?.uppercased() == "MESSAGE_REACTION_REMOVED"
    }
}

/// Simplified inbound reaction (outbound echo / legacy pull).
public struct InboundReactMessageDTO: Codable, Sendable, Equatable {
    public let userId: String
    public let conversationId: String
    public let codeMessage: String
    public let reaction: String

    public var isRemoval: Bool {
        reaction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Legacy DTOs (sync pull / older backends)
// ─────────────────────────────────────────────────────────────

public struct OutboundReactionDTO: Codable, Sendable {
    public let conversationId: String
    public let messageId: String
    public let action: String
    public let emoji: String
}

public struct InboundReactionDTO: Codable, Sendable {
    public let conversationId: String
    public let messageId: String
    public let userId: String
    public let userName: String
    public let action: String
    public let emoji: String
    public let timestamp: Double
}
