//
//  GroupPermissionsModel.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

public struct GroupPermissionsModel: Storable {
    public let id: String               // == groupLocalId
    public let groupLocalId: String
    public let groupServerId: String?
    public let sendMessages: Bool
    public let addMembers: Bool
    public let inviteLink: Bool
    public let changeGroupInfo: Bool
    public let approveNewMembers: Bool
    public let onlyAdminsCanPost: Bool
    public let sendMessagesHistory: Bool
    public let updatedAt: Date?

    public static let namespace = "chat"
    public static let schemaVersion = 1
    public static let indexedFields = ["group_local_id", "group_server_id"]
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
        case groupServerId = "group_server_id"
        case sendMessages = "send_messages"
        case addMembers = "add_members"
        case inviteLink = "invite_link"
        case changeGroupInfo = "change_group_info"
        case approveNewMembers = "approve_new_members"
        case onlyAdminsCanPost = "only_admins_can_post"
        case sendMessagesHistory = "send_messages_history"
        case updatedAt = "updated_at"
    }

    public init(
        id: String,
        groupLocalId: String,
        groupServerId: String? = nil,
        sendMessages: Bool = true,
        addMembers: Bool = true,
        inviteLink: Bool = true,
        changeGroupInfo: Bool = false,
        approveNewMembers: Bool = false,
        onlyAdminsCanPost: Bool = false,
        sendMessagesHistory: Bool = true,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.groupLocalId = groupLocalId
        self.groupServerId = groupServerId
        self.sendMessages = sendMessages
        self.addMembers = addMembers
        self.inviteLink = inviteLink
        self.changeGroupInfo = changeGroupInfo
        self.approveNewMembers = approveNewMembers
        self.onlyAdminsCanPost = onlyAdminsCanPost
        self.sendMessagesHistory = sendMessagesHistory
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        groupLocalId = try container.decode(String.self, forKey: .groupLocalId)
        groupServerId = try container.decodeIfPresent(String.self, forKey: .groupServerId)
        sendMessages = try container.decodeIfPresent(Bool.self, forKey: .sendMessages) ?? true
        addMembers = try container.decodeIfPresent(Bool.self, forKey: .addMembers) ?? true
        inviteLink = try container.decodeIfPresent(Bool.self, forKey: .inviteLink) ?? true
        changeGroupInfo = try container.decodeIfPresent(Bool.self, forKey: .changeGroupInfo) ?? false
        approveNewMembers = try container.decodeIfPresent(Bool.self, forKey: .approveNewMembers) ?? false
        onlyAdminsCanPost = try container.decodeIfPresent(Bool.self, forKey: .onlyAdminsCanPost) ?? false
        sendMessagesHistory = try container.decodeIfPresent(Bool.self, forKey: .sendMessagesHistory) ?? true
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(groupLocalId, forKey: .groupLocalId)
        try container.encodeIfPresent(groupServerId, forKey: .groupServerId)
        try container.encode(sendMessages, forKey: .sendMessages)
        try container.encode(addMembers, forKey: .addMembers)
        try container.encode(inviteLink, forKey: .inviteLink)
        try container.encode(changeGroupInfo, forKey: .changeGroupInfo)
        try container.encode(approveNewMembers, forKey: .approveNewMembers)
        try container.encode(onlyAdminsCanPost, forKey: .onlyAdminsCanPost)
        try container.encode(sendMessagesHistory, forKey: .sendMessagesHistory)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}
