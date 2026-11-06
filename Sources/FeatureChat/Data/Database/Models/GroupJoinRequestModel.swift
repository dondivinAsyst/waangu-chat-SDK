//
//  GroupJoinRequestModel.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

/// GRDB model for pending group join requests (admin approval flow).
public struct GroupJoinRequestModel: Storable {
    public let id: String
    public let groupLocalId: String
    public let userId: String
    public let name: String
    public let phone: String?
    public let avatar: String?
    public let requestedAt: Date

    public static let namespace = "chat"
    public static let schemaVersion = 1

    public static let indexedFields = [
        "group_local_id",
        "user_id",
        "requested_at"
    ]

    public static let searchableFields: [String] = [
        "name",
        "phone"
    ]

    public static let foreignKeys = [
        StorableForeignKey(
            "group_local_id",
            references: "chat_conversationmodels",
            onDelete: .cascade
        )
    ]

    enum CodingKeys: String, CodingKey {
        case id
        case groupLocalId = "group_local_id"
        case userId = "user_id"
        case name
        case phone
        case avatar
        case requestedAt = "requested_at"
    }

    public init(
        id: String,
        groupLocalId: String,
        userId: String,
        name: String,
        phone: String? = nil,
        avatar: String? = nil,
        requestedAt: Date
    ) {
        self.id = id
        self.groupLocalId = groupLocalId
        self.userId = userId
        self.name = name
        self.phone = phone
        self.avatar = avatar
        self.requestedAt = requestedAt
    }
}
