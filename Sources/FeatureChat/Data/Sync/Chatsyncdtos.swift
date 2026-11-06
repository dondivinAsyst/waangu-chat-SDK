// MARK: - FeatureChat/Data/DTOs/ChatSyncDTOs.swift


import Foundation
import WaanguCoreKit

// ═════════════════════════════════════════════════════════════════
// MARK: - Outbox Batch Request (montant : client → serveur)
// ═════════════════════════════════════════════════════════════════

public struct ChatOutboxBatchRequestDTO: Codable, Sendable {
    public let actions: [ChatOutboxActionDTO]

    public init(actions: [ChatOutboxActionDTO]) {
        self.actions = actions
    }

    public init(items: [ChatOutboxItem]) {
        self.actions = items.map { item in
            ChatOutboxActionDTO(
                localId: item.id,
                actionType: item.actionType.rawValue,
                idempotencyKey: item.idempotencyKey,
                conversationId: item.conversationId,
                payload: String(data: item.payload, encoding: .utf8) ?? "{}",
                createdAt: item.createdAt.timeIntervalSince1970
            )
        }
    }
}

public struct ChatOutboxActionDTO: Codable, Sendable {
    public let localId: String
    public let actionType: String
    public let idempotencyKey: String
    public let conversationId: String
    public let payload: String
    public let createdAt: Double

    public init(
        localId: String,
        actionType: String,
        idempotencyKey: String,
        conversationId: String,
        payload: String,
        createdAt: Double
    ) {
        self.localId = localId
        self.actionType = actionType
        self.idempotencyKey = idempotencyKey
        self.conversationId = conversationId
        self.payload = payload
        self.createdAt = createdAt
    }
}

// ═════════════════════════════════════════════════════════════════
// MARK: - Outbox Batch Response (serveur → client)
// ═════════════════════════════════════════════════════════════════

public struct ChatOutboxBatchResponseDTO: Codable, Sendable {
    public let syncTimestamp: Double
    public let results: [ChatOutboxResultDTO]
}

public struct ChatOutboxResultDTO: Codable, Sendable {
    public let localId: String
    public let success: Bool
    public let serverId: String?
    public let serverTimestamp: Double?
    public let error: String?
    public let errorCode: String?
    public let retryable: Bool?

    public func toFlushResult() -> OutboxFlushResult {
        OutboxFlushResult(
            localId: localId,
            success: success,
            serverId: serverId,
            serverTimestamp: serverTimestamp.map { Date(timeIntervalSince1970: $0) },
            error: error,
            errorCode: errorCode,
            retryable: retryable
        )
    }
}

// ═════════════════════════════════════════════════════════════════
// MARK: - Sync Event Envelope (descendant : serveur → client)
// ═════════════════════════════════════════════════════════════════

/// Enveloppe d'événement de synchro — reçue via pull HTTP et MQTT live.
///
/// Le `type` détermine quel Inbound*DTO existant se trouve dans `payload` :
///
///   type                      → decodePayload(as:)
///   ─────────────────────────────────────────────────────
///   "message"                 → InboundMessageDTO
///   "reaction"                → BackendMessageReactionEventDTO / InboundReactMessageDTO
///   "reaction_removed"        → BackendMessageReactionEventDTO
///   "pin"                     → InboundPinEventDTO
///   "delivery_receipt"        → InboundDeliveryReceiptDTO
///   "message_edited"          → InboundMessageEditDTO
///   "message_deleted"         → InboundMessageDeleteDTO
///   "delete_ack" / "delete_failed" → delete-for-everyone ACK
///   "participant_event"       → InboundParticipantEventDTO
///   "conversation_event"      → InboundConversationEventDTO
///   "status_event"            → InboundStatusEventDTO (legacy)
///   "story_created"           → InboundStoryCreatedDTO
///   "story_viewed"            → InboundStoryViewedDTO
///   "story_deleted"           → InboundStoryDeletedDTO
///   "story_reacted"           → InboundStoryReactedDTO
///   "story_expired"           → InboundStoryExpiredDTO
///   "user_presence"           → PresencePayloadDTO
///   "presence"                → InboundPresenceDTO (MQTT typing uniquement)
///   "call_event"              → InboundCallEventDTO (MQTT uniquement)
public struct ChatSyncEventDTO: Codable, Sendable {
    public let type: String
    public let referenceId: String?
    public let conversationId: String?
    public let payload: AnyCodablePayload?
    public let at: Double

    public var date: Date { Date(timeIntervalSince1970: at) }

    /// The type given to a `SESSION_REVOKED` event once parsed.
    static let sessionRevokedType = "session_revoked"
    var isSessionRevocation: Bool { type == Self.sessionRevokedType }

    /// Décode le payload vers un Inbound*DTO existant.
    public func decodePayload<T: Decodable>(as type: T.Type) -> T? {
        guard let data = payload?.rawData else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Capture le JSON brut du payload sans le décoder immédiatement.
public struct AnyCodablePayload: Codable, Sendable {
    public let rawData: Data

    public init(rawData: Data) { self.rawData = rawData }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: CodableValue].self) {
            rawData = try JSONEncoder().encode(dict)
        } else if let array = try? container.decode([CodableValue].self) {
            rawData = try JSONEncoder().encode(array)
        } else if let str = try? container.decode(String.self),
                  let data = str.data(using: .utf8) {
            rawData = data
        } else {
            rawData = Data()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let obj = try? JSONSerialization.jsonObject(with: rawData) {
            try container.encode(CodableValue(obj))
        }
    }
}

// ═════════════════════════════════════════════════════════════════
// MARK: - Inbox Summary (phase 1)
// ═════════════════════════════════════════════════════════════════

public struct ChatInboxSummaryResponseDTO: Codable, Sendable {
    public let conversations: [ChatConversationSummaryDTO]
    public let syncTimestamp: Double
}

// ═════════════════════════════════════════════════════════════════
// MARK: - Pull Events Response (phase 3)
// ═════════════════════════════════════════════════════════════════

public struct ChatPullEventsResponseDTO: Codable, Sendable {
    public let events: [ChatSyncEventDTO]
    public let nextCursor: String?
    public let hasMore: Bool
}

public struct ChatConversationSummaryDTO: Codable, Sendable {
    public let id: String
    public let type: String
    public let title: String?
    public let avatarURL: String?
    public let participantIds: [String]
    public let lastMessage: InboundMessageDTO?
    public let unreadCount: Int
    public let updatedAt: Double
    public let status: String
    public let mutedUntil: Double?
    public let pinnedAt: Double?
}

// ═════════════════════════════════════════════════════════════════
// MARK: - CodableValue helper
// ═════════════════════════════════════════════════════════════════

enum CodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([CodableValue])
    case dict([String: CodableValue])
    case null

    init(_ value: Any) {
        switch value {
        case let b as Bool:          self = .bool(b)
        case let i as Int:           self = .int(i)
        case let d as Double:        self = .double(d)
        case let s as String:        self = .string(s)
        case let a as [Any]:         self = .array(a.map { CodableValue($0) })
        case let d as [String: Any]: self = .dict(d.mapValues { CodableValue($0) })
        default:                     self = .null
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self)                        { self = .bool(b) }
        else if let i = try? container.decode(Int.self)                    { self = .int(i) }
        else if let d = try? container.decode(Double.self)                 { self = .double(d) }
        else if let s = try? container.decode(String.self)                 { self = .string(s) }
        else if let a = try? container.decode([CodableValue].self)         { self = .array(a) }
        else if let d = try? container.decode([String: CodableValue].self) { self = .dict(d) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .array(let v):  try container.encode(v)
        case .dict(let v):   try container.encode(v)
        case .null:          try container.encodeNil()
        }
    }
}
