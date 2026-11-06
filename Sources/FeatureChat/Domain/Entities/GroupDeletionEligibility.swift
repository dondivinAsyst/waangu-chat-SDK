//
//  GroupDeletionEligibility.swift
//  FeatureChat
//
//  Represents the deletion eligibility status and user guidance for groups
//

import Foundation

// MARK: - Deletion Eligibility

/// Represents whether a group or discussion can be deleted and why
public struct DeletionEligibility: Equatable {
    /// Whether the item can be permanently deleted
    public let canDelete: Bool
    
    /// The reason deletion is allowed or blocked
    public let reason: DeletionBlockReason
    
    /// User-facing message explaining the status
    public let userMessage: String
    
    /// Suggested action for the user
    public let suggestedAction: DeletionAction
    
    /// Additional context for UI
    public let metadata: DeletionMetadata
    
    public init(
        canDelete: Bool,
        reason: DeletionBlockReason,
        userMessage: String,
        suggestedAction: DeletionAction,
        metadata: DeletionMetadata
    ) {
        self.canDelete = canDelete
        self.reason = reason
        self.userMessage = userMessage
        self.suggestedAction = suggestedAction
        self.metadata = metadata
    }
}

// MARK: - Deletion Block Reason

/// Why deletion is blocked or allowed
public enum DeletionBlockReason: Equatable {
    // Allowed
    case regularDiscussion
    case lastMemberOrLeft
    case notAMember
    
    // Blocked
    case stillActiveMember(memberCount: Int)
    case groupHasOtherMembers(activeMembers: Int)
    
    public var isAllowed: Bool {
        switch self {
        case .regularDiscussion, .lastMemberOrLeft, .notAMember:
            return true
        case .stillActiveMember, .groupHasOtherMembers:
            return false
        }
    }
}

// MARK: - Deletion Action

/// What action the user should take
public enum DeletionAction: Equatable {
    // Direct actions
    case deleteNow
    case deleteLocalContent
    
    // Prerequisite actions
    case leaveGroupFirst
    case leaveAndDelete
    
    // Informational
    case cannotDelete
}

// MARK: - Deletion Metadata

/// Additional context for UI display
public struct DeletionMetadata: Equatable {
    /// Whether this is a group discussion
    public let isGroup: Bool
    
    /// Whether the user is currently a member
    public let isMember: Bool
    
    /// Whether the user is the last active member
    public let isLastMember: Bool
    
    /// Total number of active members
    public let activeMemberCount: Int
    
    /// Whether the user can leave the group
    public let canLeave: Bool
    
    /// Whether the user can remove local discussion content without deleting the group
    public let canDeleteLocalContent: Bool
    
    /// Group name (if applicable)
    public let groupName: String?
    
    public init(
        isGroup: Bool,
        isMember: Bool,
        isLastMember: Bool,
        activeMemberCount: Int,
        canLeave: Bool,
        canDeleteLocalContent: Bool = false,
        groupName: String? = nil
    ) {
        self.isGroup = isGroup
        self.isMember = isMember
        self.isLastMember = isLastMember
        self.activeMemberCount = activeMemberCount
        self.canLeave = canLeave
        self.canDeleteLocalContent = canDeleteLocalContent
        self.groupName = groupName
    }
}

// MARK: - Deletion Result

/// Result of a deletion attempt
public enum DeletionResult: Equatable {
    case success
    case blocked(reason: String)
    case requiresLeave(groupId: String)
    case requiresLeaveAndDelete(groupId: String)
    case error(message: String)
}

// MARK: - Leave Group Outcome

public enum LeaveGroupOutcome: Equatable {
    case left
}

public struct PostLeaveLocalCleanupContext: Identifiable, Equatable {
    public let id: String
    public let discussionId: String
    public let groupName: String
    
    public init(discussionId: String, groupName: String) {
        self.id = discussionId
        self.discussionId = discussionId
        self.groupName = groupName
    }
    
    public var userMessage: String {
        "You left \"\(groupName)\". Keep the chat in your inbox or delete it for you?"
    }
}

extension DeletionDialogContext {
    public var exitGroupPromptMessage: String {
        let name = eligibility.metadata.groupName ?? "this group"
        return "You will leave \"\(name)\" for everyone. Exit keeps the chat in your inbox (view only). Exit and delete for me removes the chat for you."
    }
}

// MARK: - Deletion Dialog Intent

public enum DeletionDialogIntent: Equatable {
    case deleteFromList
    case exitGroup
    case deleteFromGroupInfo
}

public struct DeletionDialogContext: Identifiable, Equatable {
    public let id: String
    public let discussionId: String
    public let eligibility: DeletionEligibility
    public let intent: DeletionDialogIntent
    
    public init(
        discussionId: String,
        eligibility: DeletionEligibility,
        intent: DeletionDialogIntent
    ) {
        self.id = discussionId
        self.discussionId = discussionId
        self.eligibility = eligibility
        self.intent = intent
    }
}

// MARK: - Helper Extensions

extension DeletionEligibility {
    /// Creates eligibility for a regular (non-group) discussion
    public static func regularDiscussion() -> DeletionEligibility {
        DeletionEligibility(
            canDelete: true,
            reason: .regularDiscussion,
            userMessage: "Delete this conversation?",
            suggestedAction: .deleteNow,
            metadata: DeletionMetadata(
                isGroup: false,
                isMember: false,
                isLastMember: false,
                activeMemberCount: 0,
                canLeave: false
            )
        )
    }
    
    /// Creates eligibility for a user who is still an active group member
    public static func stillActiveMember(
        groupName: String,
        memberCount: Int
    ) -> DeletionEligibility {
        DeletionEligibility(
            canDelete: false,
            reason: .stillActiveMember(memberCount: memberCount),
            userMessage: "You are still a member of \"\(groupName)\". You can clear messages and keep the chat in your inbox, or leave the group first.",
            suggestedAction: .leaveGroupFirst,
            metadata: DeletionMetadata(
                isGroup: true,
                isMember: true,
                isLastMember: false,
                activeMemberCount: memberCount,
                canLeave: true,
                canDeleteLocalContent: true,
                groupName: groupName
            )
        )
    }
    
    /// Creates eligibility for a user who is the last member
    public static func lastMember(groupName: String) -> DeletionEligibility {
        DeletionEligibility(
            canDelete: false,
            reason: .lastMemberOrLeft,
            userMessage: "You are the only member of \"\(groupName)\". After leaving, you can keep the chat in your inbox or delete it for you.",
            suggestedAction: .leaveGroupFirst,
            metadata: DeletionMetadata(
                isGroup: true,
                isMember: true,
                isLastMember: true,
                activeMemberCount: 1,
                canLeave: true,
                canDeleteLocalContent: true,
                groupName: groupName
            )
        )
    }
    
    /// Creates eligibility for a user who has already left the group
    public static func alreadyLeft(
        groupName: String,
        hasOtherMembers: Bool,
        activeMemberCount: Int
    ) -> DeletionEligibility {
        let message = hasOtherMembers
            ? "You left \"\(groupName)\". Delete for me removes this chat for you. The group continues for other members."
            : "Delete \"\(groupName)\" and all messages?"
        
        return DeletionEligibility(
            canDelete: true,
            reason: .notAMember,
            userMessage: message,
            suggestedAction: .deleteLocalContent,
            metadata: DeletionMetadata(
                isGroup: true,
                isMember: false,
                isLastMember: false,
                activeMemberCount: activeMemberCount,
                canLeave: false,
                canDeleteLocalContent: true,
                groupName: groupName
            )
        )
    }
}

extension DeletionEligibility {
    public var dialogTitle: String {
        switch suggestedAction {
        case .deleteNow, .deleteLocalContent:
            return "Delete Conversation"
        case .leaveGroupFirst:
            return ChatErrorStrings.cannotDeleteGroupTitle
        case .leaveAndDelete:
            return intentTitle(for: .exitGroup)
        case .cannotDelete:
            return ChatErrorStrings.cannotDeleteShort
        }
    }
    
    public func intentTitle(for intent: DeletionDialogIntent) -> String {
        switch intent {
        case .exitGroup:
            return "Exit Group"
        case .deleteFromList, .deleteFromGroupInfo:
            return "Delete Conversation"
        }
    }
    
    public var primaryButtonTitle: String {
        switch suggestedAction {
        case .deleteNow:
            return "Delete"
        case .deleteLocalContent:
            return "Delete for Me"
        case .leaveGroupFirst:
            return "Leave Group"
        case .leaveAndDelete:
            return "Leave and Delete"
        case .cannotDelete:
            return "OK"
        }
    }
}
