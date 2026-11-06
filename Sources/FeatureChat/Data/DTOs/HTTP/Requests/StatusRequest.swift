import Foundation
import WaanguCoreKit

struct CreateStatusRequest: Codable {
    let storyId: String
    let creatorId: String
    let content: String?
    let storyType: String
    let caption: String?
    let thumbnail: String?
    let font: String?
    let background: String?
    let expiresAt: String
    let tenantId: String
    let country: String

    init(from story: StoryToSend) {
        storyId = story.id
        creatorId = story.userId
        content = story.content
        storyType = story.type.apiValue
        caption = story.caption
        thumbnail = story.thumbnail
        font = Self.composeFont(text: story.fontText, weight: story.fontWeight)
        background = story.background
        expiresAt = Self.iso8601(
            Calendar.current.date(byAdding: .hour, value: story.expiresInHours, to: Date()) ?? Date()
        )
        tenantId = CurrentSessionInfo.shared.tenantId
        country = CurrentSessionInfo.shared.country
    }

    func toDictionary() throws -> [String: Any] {
        try StatusRequestEncoding.toDictionary(self)
    }

    private static func composeFont(text: String?, weight: String?) -> String? {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWeight = weight?.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasText = !(trimmedText?.isEmpty ?? true)
        let hasWeight = !(trimmedWeight?.isEmpty ?? true)

        switch (hasText, hasWeight) {
        case (true, true):
            return "\(trimmedText!)|\(trimmedWeight!)"
        case (true, false):
            return trimmedText
        case (false, true):
            return trimmedWeight
        case (false, false):
            return nil
        }
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// DELETE `/chat-core/stories` body — same shape as MQTT `OutboundDeleteStoryDTO`.
struct DeleteStatusRequest: Codable {
    let storyId: String
    let deletedBy: String
    let tenantId: String
    let country: String

    init(
        storyId: String,
        deletedBy: String = CurrentSessionInfo.shared.currentUid,
        tenantId: String = CurrentSessionInfo.shared.tenantId,
        country: String = CurrentSessionInfo.shared.country
    ) {
        self.storyId = storyId
        self.deletedBy = deletedBy
        self.tenantId = tenantId
        self.country = country
    }

    func toDictionary() throws -> [String: Any] {
        try StatusRequestEncoding.toDictionary(self)
    }
}

private enum StatusRequestEncoding {
    static func toDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.compactMapValues { value in
            value is NSNull ? nil : value
        }
    }
}
