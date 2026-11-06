//
//  ChatRoomGroupIntroCoordinator.swift
//  FeatureChat
//

import Foundation

/// Group intro card visibility and dismissal persistence.
enum ChatRoomGroupIntroCoordinator {

    static func isUserGeneratedMessage(_ message: MessageDataItem) -> Bool {
        !message.isDeleted && message.typeMessage != .GROUP_CREATED
    }

    static func hasUserGeneratedMessages(in messages: [MessageDataItem]) -> Bool {
        messages.contains(where: isUserGeneratedMessage)
    }

    static func shouldShowIntro(isGroup: Bool, hasBeenDismissed: Bool) -> Bool {
        isGroup && !hasBeenDismissed
    }

    static func loadDismissedState(isGroup: Bool, conversationId: String) -> Bool {
        guard isGroup else { return false }
        return GroupIntroDismissalStore.isDismissed(conversationId: conversationId)
    }

    static func shouldAutoDismiss(
        isGroup: Bool,
        hasBeenDismissed: Bool,
        messages: [MessageDataItem]
    ) -> Bool {
        isGroup && !hasBeenDismissed && hasUserGeneratedMessages(in: messages)
    }

    static func markDismissed(conversationId: String) {
        GroupIntroDismissalStore.markDismissed(conversationId: conversationId)
    }

    static func makeContent(
        groupName: String,
        description: String?,
        memberCount: Int,
        avatarUrl: String?,
        createdByCurrentUser: Bool,
        canAddMembers: Bool,
        canShowInviteLink: Bool
    ) -> GroupChatIntroContent {
        GroupChatIntroContent(
            groupName: groupName,
            description: description,
            memberCount: memberCount,
            avatarUrl: avatarUrl,
            createdByCurrentUser: createdByCurrentUser,
            canAddMembers: canAddMembers,
            canShowInviteLink: canShowInviteLink
        )
    }
}
