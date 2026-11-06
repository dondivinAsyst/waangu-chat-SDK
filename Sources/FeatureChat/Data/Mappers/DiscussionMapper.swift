import Foundation

// DiscussionModel and the separate SettingModel no longer exist.
// A conversation is a ConversationModel with type == .direct, .group or .channel.
// The mapper now bridges DiscussionChatItem ↔ ConversationModel.

protocol DiscussionMapperProtocol {
    func toDomain(_ grdb: ConversationModel) -> DiscussionChatItem
    func toGRDB(_ discussion: DiscussionChatItem) -> ConversationModel
}

final class DiscussionMapper: DiscussionMapperProtocol {

    func toGRDB(_ discussion: DiscussionChatItem) -> ConversationModel {
        let isChannel = discussion.contact?.isChannel ?? false
        let isGroup = discussion.contact?.isGroup ?? false
        return ConversationModel(
            id: discussion.conversationId,
            type: isChannel ? .channel : (isGroup ? .group : .direct),
            title: isGroup ? discussion.contact?.userName : nil,
            avatarURL: discussion.contact?.image,
            lastMessageText: discussion.lastMessage.message.text.isEmpty ? nil : discussion.lastMessage.message.text,
            lastMessageType: nil,
            lastMessageSenderName: discussion.lastMessage.senderName.isEmpty ? nil : discussion.lastMessage.senderName,
            lastMessageAt: discussion.lastMessage.createdAt,
            unreadCount: discussion.count,
            isPinned: discussion.setting?.isPinned ?? false,
            isArchived: discussion.setting?.isArchived ?? false,
            draft: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func toDomain(_ grdb: ConversationModel) -> DiscussionChatItem {
        let isChannel = grdb.type == .channel
        let isGroup = grdb.type.isMultiParty
        return DiscussionChatItem(
            lastMessage: MessageDataItem(
                codeMessage: UUID().uuidString.lowercased(),
                senderId: "",
                groupId: isGroup ? grdb.id : "",
                typeMessage: .TEXT,
                message: MessageContent(text: grdb.lastMessageText ?? Self.emptyPreview(isGroup: isGroup, isChannel: isChannel)),
                status: .PENDING,
                createdAt: grdb.lastMessageAt ?? grdb.createdAt
            ),
            conversationId: grdb.id,
            contact: ContactChannel(
                userName: grdb.title ?? "",
                phone: "",
                image: grdb.avatarURL,
                isBlocked: false,
                isGroup: isGroup,
                isChannel: isChannel,
                id: grdb.id
            ),
            count: grdb.unreadCount,
            setting: UserConversationSetting(
                isPinned: grdb.isPinned,
                isArchived: grdb.isArchived
            )
        )
    }

    /// Subtitle for a conversation that has no message yet.
    private static func emptyPreview(isGroup: Bool, isChannel: Bool) -> String {
        if isChannel { return "Channel created" }
        return isGroup ? "Group created" : "Conversation started"
    }
}
