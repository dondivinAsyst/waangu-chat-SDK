//
//  GroupSettingsModel.swift
//  AppModules
//
//  Created by Asyst on 6/25/26.
//

import Foundation
import WaanguCoreKit

/// Persisted `GroupSettings` for one group conversation.
///
/// These used to be encoded into `ConversationModel.draft` — a stopgap that took
/// the only free string column on the conversation. That column now carries the
/// composer draft, which every conversation has and the chat list renders in
/// place of the last message, so the settings moved here.
///
/// The settings ride as a JSON blob rather than one column per flag: they are
/// read and written whole, never queried field by field, and `GroupSettings`
/// gains fields often enough that a column per flag would mean a field migration
/// each time.
public struct GroupSettingsModel: Storable {

    /// Same value as `groupLocalId` — one settings row per group.
    public let id: String
    public let groupLocalId: String
    /// JSON encoding of `GroupSettings`.
    public let settingsJSON: String
    public let updatedAt: Date?

    public static let namespace = "chat"
    public static let schemaVersion = 1
    public static let indexedFields = ["group_local_id"]
    public static let searchableFields: [String] = []
    public static let foreignKeys: [StorableForeignKey] = [
        StorableForeignKey(
            "group_local_id",
            references: "chat_conversationmodels",
            onDelete: .cascade
        )
    ]

    enum CodingKeys: String, CodingKey {
        case id
        case groupLocalId = "group_local_id"
        case settingsJSON = "settings_json"
        case updatedAt = "updated_at"
    }

    public init(
        groupLocalId: String,
        settingsJSON: String,
        updatedAt: Date? = Date()
    ) {
        self.id = groupLocalId
        self.groupLocalId = groupLocalId
        self.settingsJSON = settingsJSON
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        groupLocalId = try container.decode(String.self, forKey: .groupLocalId)
        settingsJSON = try container.decodeIfPresent(String.self, forKey: .settingsJSON) ?? ""
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(groupLocalId, forKey: .groupLocalId)
        try container.encode(settingsJSON, forKey: .settingsJSON)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - GroupSettings bridging

extension GroupSettingsModel {

    /// Nil when the settings cannot be encoded — the caller then leaves whatever
    /// row already exists alone rather than storing an unreadable one.
    static func make(groupLocalId: String, settings: GroupSettings) -> GroupSettingsModel? {
        guard let data = try? JSONEncoder().encode(settings),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return GroupSettingsModel(groupLocalId: groupLocalId, settingsJSON: json)
    }

    /// Defaults when the row is missing or unreadable — same fallback the
    /// `draft`-based decoding used.
    var settings: GroupSettings {
        guard let data = settingsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(GroupSettings.self, from: data) else {
            return GroupSettings()
        }
        return decoded
    }
}
