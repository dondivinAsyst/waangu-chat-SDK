//
//  CreateGroupWithDiscussionModels.swift
//  FeatureChat
//

import Foundation

// MARK: - Input

public struct CreateGroupWithDiscussionInput: Sendable {
    public let groupName: String
    public let invitedMembers: [UserContactProps]
    public let avatarUrl: String?
    public let settings: GroupSettings

    public init(
        groupName: String,
        invitedMembers: [UserContactProps],
        avatarUrl: String? = nil,
        settings: GroupSettings = GroupSettings()
    ) {
        self.groupName = groupName
        self.invitedMembers = invitedMembers
        self.avatarUrl = avatarUrl
        self.settings = settings
    }
}

// MARK: - Result

public struct CreateGroupWithDiscussionResult: Sendable {
    public let group: GroupChat
    public let discussion: DiscussionChatItem?  // ✅ Optional - created only after successful sync

    public init(group: GroupChat, discussion: DiscussionChatItem?) {
        self.group = group
        self.discussion = discussion
    }
}

// MARK: - Errors

public enum CreateGroupError: LocalizedError {
    case emptyGroupName

    public var errorDescription: String? {
        switch self {
        case .emptyGroupName:
            return "Group name cannot be empty."
        }
    }
}
