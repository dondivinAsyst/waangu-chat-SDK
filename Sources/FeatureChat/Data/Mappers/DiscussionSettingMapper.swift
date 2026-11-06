//
//  DiscussionSettingMapper.swift
//  FeatureChat
//
//  Settings are stored in two places:
//   - ConversationModel: isPinned, isArchived (fast fields for list sorting)
//   - ChatPreferenceModel: all rich settings (mute, lock, wallpaper, ephemeral, etc.)
//
//  This mapper bridges UserConversationSetting ↔ both models.
//

import Foundation

enum DiscussionSettingMapper {

    // MARK: - ConversationModel ↔ UserConversationSetting (pin/archive only)

    /// Apply pin/archive from a setting onto a ConversationModel, returning updated copy.
    static func apply(
        _ setting: UserConversationSetting,
        to conversation: ConversationModel
    ) -> ConversationModel {
        ConversationModel(
            id: conversation.id,
            serverId: conversation.serverId,
            type: conversation.type,
            title: conversation.title,
            avatarURL: conversation.avatarURL,
            lastMessageText: conversation.lastMessageText,
            lastMessageType: conversation.lastMessageType,
            lastMessageSenderName: conversation.lastMessageSenderName,
            lastMessageAt: conversation.lastMessageAt,
            unreadCount: conversation.unreadCount,
            isPinned: setting.isPinned ?? conversation.isPinned,
            isArchived: setting.isArchived ?? conversation.isArchived,
            draft: conversation.draft,
            isShowingDraft: conversation.isShowingDraft,
            assignedAgentName: conversation.assignedAgentName,
            lastReadMessageId: conversation.lastReadMessageId,
            createdAt: conversation.createdAt,
            updatedAt: Date()
        )
    }

    /// Extract pin/archive from a ConversationModel into a partial UserConversationSetting.
    static func toDomain(_ conversation: ConversationModel) -> UserConversationSetting {
        UserConversationSetting(
            conversation: conversation.id,
            isPinned: conversation.isPinned,
            isArchived: conversation.isArchived
        )
    }

    // MARK: - ChatPreferenceModel ↔ UserConversationSetting (full preferences)

    /// Build a full UserConversationSetting by merging ConversationModel (pin/archive)
    /// with a ChatPreferenceModel (mute, ephemeral, lock, etc.).
    static func mergedSetting(
        from conversation: ConversationModel,
        preference: ChatPreferenceModel?
    ) -> UserConversationSetting {
        UserConversationSetting(
            conversation: conversation.id,
            isMuted: preference?.isMuted,
            muteEndAt: preference?.mutedUntil,
            isPinned: conversation.isPinned,
            isArchived: conversation.isArchived,
            ephemeralMessageDuration: preference?.disappearingMessagesSeconds,
            updatedAt: preference?.updatedAt ?? conversation.updatedAt
        )
    }
}
