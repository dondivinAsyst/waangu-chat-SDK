import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: Outbound story MQTT DTOs
// ─────────────────────────────────────────────────────────────
// Published to `waangu-chat/view-story`, `delete-story`, `react-story`.

public struct OutboundViewStoryDTO: Codable, Sendable, Equatable {
    public let storyId: String
    public let viewerId: String
    public let tenantId: String
    public let country: String

    public init(
        storyId: String,
        viewerId: String,
        tenantId: String = CurrentSessionInfo.shared.tenantId,
        country: String = CurrentSessionInfo.shared.country
    ) {
        self.storyId = storyId
        self.viewerId = viewerId
        self.tenantId = tenantId
        self.country = country
    }
}

public struct OutboundDeleteStoryDTO: Codable, Sendable, Equatable {
    public let storyId: String
    public let deletedBy: String
    public let tenantId: String
    public let country: String

    public init(
        storyId: String,
        deletedBy: String,
        tenantId: String,
        country: String
    ) {
        self.storyId = storyId
        self.deletedBy = deletedBy
        self.tenantId = tenantId
        self.country = country
    }
}

public struct OutboundReactStoryDTO: Codable, Sendable, Equatable {
    public let storyId: String
    public let userId: String
    public let reaction: String
    public let creatorId: String?
    public let tenantId: String
    public let country: String

    public init(
        storyId: String,
        userId: String,
        reaction: String,
        creatorId: String? = nil,
        tenantId: String = CurrentSessionInfo.shared.tenantId,
        country: String = CurrentSessionInfo.shared.country
    ) {
        self.storyId = storyId
        self.userId = userId
        self.reaction = reaction
        self.creatorId = creatorId
        self.tenantId = tenantId
        self.country = country
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Inbound story MQTT DTOs
// ─────────────────────────────────────────────────────────────
// Received on `waangu-chat/{userId}` with `eventType` = STORY_*.

/// `STORY_CREATED` — a contact posted a new story segment.
///
/// Wire shape (nested under root `payload`):
/// ```
/// storyId, creatorId, content, storyType, caption, thumbnail,
/// font, background, expiresAt, createdAt, tenantId, country,
/// idempotencyKey, eventType, eventVersion
/// ```
public struct InboundStoryCreatedDTO: Codable, Sendable {
    public let storyId: String?
    public let id: String?
    public let codeStatus: String?
    public let creatorId: String?
    public let userId: String?
    public let creatorName: String?
    public let userName: String?
    public let creatorAvatar: String?
    public let userImage: String?
    public let avatarURL: String?
    public let storyType: String?
    public let type: String?
    public let content: String?
    public let text: String?
    public let caption: String?
    public let thumbnail: String?
    public let thumbnailURL: String?
    public let font: String?
    public let fontText: String?
    public let fontWeight: String?
    public let background: String?
    public let backgroundColor: String?
    public let segmentIndex: Int?
    public let totalSegments: Int?
    public let expiresAt: String?
    public let createdAt: String?
    public let timestamp: Double?
    public let tenantId: String?
    public let country: String?
    public let idempotencyKey: String?
    public let eventType: String?
    public let eventVersion: Int?

    public var resolvedStoryId: String {
        let primary = storyId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty { return primary }
        let legacy = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacy.isEmpty { return legacy }
        return codeStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var resolvedCreatorId: String {
        let creator = creatorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !creator.isEmpty { return creator }
        return userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var resolvedCreatorName: String {
        let name = (creatorName ?? userName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name
    }

    public var resolvedCreatorAvatar: String? {
        nonEmpty(creatorAvatar) ?? nonEmpty(userImage) ?? nonEmpty(avatarURL)
    }

    public var resolvedStoryType: String {
        let value = (storyType ?? type)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "TEXT" : value
    }

    /// Media URL / text body. Decodes HTML entities (`&amp;` → `&`) from signed S3 URLs.
    public var resolvedContent: String? {
        guard let raw = nonEmpty(content) ?? nonEmpty(text) else { return nil }
        return Self.decodeHTMLEntities(raw)
    }

    public var resolvedCaption: String? {
        nonEmpty(caption)
    }

    public var resolvedThumbnail: String? {
        nonEmpty(thumbnail) ?? nonEmpty(thumbnailURL)
    }

    public var resolvedBackground: String? {
        nonEmpty(background) ?? nonEmpty(backgroundColor)
    }

    public var resolvedFont: String? {
        nonEmpty(font) ?? nonEmpty(fontText)
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

/// `STORY_VIEWED` — someone viewed my story.
/// Wire: `ViewStoryPayload { storyId, viewerId, creatorId?, tenantId?, country? }`
public struct InboundStoryViewedDTO: Codable, Sendable {
    public let storyId: String?
    public let viewerId: String?
    public let creatorId: String?
    public let tenantId: String?
    public let country: String?

    /// Legacy aliases (older brokers).
    public let id: String?
    public let codeStatus: String?
    public let userId: String?

    public var resolvedStoryId: String {
        let primary = storyId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty { return primary }
        let legacy = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacy.isEmpty { return legacy }
        return codeStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var resolvedViewerId: String {
        let viewer = viewerId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !viewer.isEmpty { return viewer }
        return userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var resolvedCreatorId: String {
        creatorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// `STORY_DELETED` — a contact deleted their story (or multi-device own delete).
///
/// Envelope:
/// ```
/// { eventType, payload, muted, suppressNotification, timestamp }
/// ```
/// Payload wire shape:
/// ```
/// storyId, deletedBy, deletedAt (epoch ms), tenantId, country,
/// eventType, eventVersion
/// ```
public struct InboundStoryDeletedDTO: Codable, Sendable {
    public let storyId: String?
    public let id: String?
    public let codeStatus: String?
    public let deletedBy: String?
    public let creatorId: String?
    public let userId: String?
    public let tenantId: String?
    public let country: String?
    /// Epoch millis (preferred) or seconds — server sends a number.
    public let deletedAt: Double?
    public let timestamp: Double?
    public let eventType: String?
    public let eventVersion: Int?

    private enum CodingKeys: String, CodingKey {
        case storyId, id, codeStatus, deletedBy, creatorId, userId
        case tenantId, country, deletedAt, timestamp, eventType, eventVersion
    }

    public init(
        storyId: String? = nil,
        id: String? = nil,
        codeStatus: String? = nil,
        deletedBy: String? = nil,
        creatorId: String? = nil,
        userId: String? = nil,
        tenantId: String? = nil,
        country: String? = nil,
        deletedAt: Double? = nil,
        timestamp: Double? = nil,
        eventType: String? = nil,
        eventVersion: Int? = nil
    ) {
        self.storyId = storyId
        self.id = id
        self.codeStatus = codeStatus
        self.deletedBy = deletedBy
        self.creatorId = creatorId
        self.userId = userId
        self.tenantId = tenantId
        self.country = country
        self.deletedAt = deletedAt
        self.timestamp = timestamp
        self.eventType = eventType
        self.eventVersion = eventVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storyId = try container.decodeIfPresent(String.self, forKey: .storyId)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        codeStatus = try container.decodeIfPresent(String.self, forKey: .codeStatus)
        deletedBy = try container.decodeIfPresent(String.self, forKey: .deletedBy)
        creatorId = try container.decodeIfPresent(String.self, forKey: .creatorId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        tenantId = try container.decodeIfPresent(String.self, forKey: .tenantId)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        eventType = try container.decodeIfPresent(String.self, forKey: .eventType)
        eventVersion = try container.decodeIfPresent(Int.self, forKey: .eventVersion)
        deletedAt = Self.decodeEpoch(from: container, forKey: .deletedAt)
        timestamp = Self.decodeEpoch(from: container, forKey: .timestamp)
    }

    public var resolvedStoryId: String {
        let primary = storyId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty { return primary }
        let legacy = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacy.isEmpty { return legacy }
        return codeStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var resolvedDeletedBy: String {
        let by = deletedBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !by.isEmpty { return by }
        let creator = creatorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !creator.isEmpty { return creator }
        return userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Prefer payload `deletedAt` (epoch ms), then `timestamp`.
    public var resolvedDeletedAt: Date? {
        if let deletedAt {
            let seconds = deletedAt > 10_000_000_000 ? deletedAt / 1_000 : deletedAt
            return Date(timeIntervalSince1970: seconds)
        }
        if let timestamp {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    /// Backward-compatible alias.
    public var resolvedCreatorId: String { resolvedDeletedBy }

    private static func decodeEpoch(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return Double(value)
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let raw = try? container.decodeIfPresent(String.self, forKey: key),
           !raw.isEmpty {
            if let number = Double(raw) {
                return number
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) {
                return date.timeIntervalSince1970 * 1_000
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: raw) {
                return date.timeIntervalSince1970 * 1_000
            }
        }
        return nil
    }
}

/// `STORY_REACTED` — someone reacted to my story.
/// Wire: `ReactToStoryPayload { storyId, userId, reaction, creatorId?, tenantId?, country? }`
public struct InboundStoryReactedDTO: Codable, Sendable {
    public let storyId: String?
    public let userId: String?
    public let reaction: String?
    public let creatorId: String?
    public let tenantId: String?
    public let country: String?

    /// Legacy aliases (older brokers).
    public let id: String?
    public let codeStatus: String?
    public let senderId: String?
    public let emoji: String?

    public var resolvedStoryId: String {
        let primary = storyId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty { return primary }
        let legacy = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacy.isEmpty { return legacy }
        return codeStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var resolvedReactorId: String {
        let user = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !user.isEmpty { return user }
        return senderId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var resolvedReaction: String {
        let value = reaction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !value.isEmpty { return value }
        return emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var resolvedCreatorId: String {
        creatorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// `STORY_EXPIRED` — a story segment expired (24h TTL).
public struct InboundStoryExpiredDTO: Codable, Sendable {
    public let storyId: String?
    public let id: String?
    public let codeStatus: String?
    public let creatorId: String?
    public let userId: String?
    public let expiredAt: String?
    public let timestamp: Double?
    public let eventType: String?

    public var resolvedStoryId: String {
        let primary = storyId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty { return primary }
        let legacy = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacy.isEmpty { return legacy }
        return codeStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var resolvedCreatorId: String {
        let creator = creatorId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !creator.isEmpty { return creator }
        return userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
