import Foundation

/// A record the backend writes into a conversation about the conversation
/// itself — created, contact blocked, messages cleared — rather than a message
/// anyone sent.
///
/// It is never a bubble. The history sync already turned these into
/// checkpoints; realtime, pull events and the inbox summary stored them as
/// messages, and `"SYSTEM"` reads back as text, so "CONVERSATION_CREATED"
/// showed in the thread and in the chat list. Every inbound path asks here.
enum ConversationSystemRecord {

    enum Kind: Equatable {
        /// Housekeeping: the thread starting says nothing worth showing.
        case conversationCreated
        /// Shown as a checkpoint.
        case action(ChatActionType)
        /// A system record this app does not know how to show — dropped rather
        /// than printed raw.
        case unknown
    }

    /// Nil for anything that is not a conversation system record — including
    /// group events and call records, which have their own handling.
    static func kind(of dto: InboundMessageDTO) -> Kind? {
        guard dto.resolvedGroupEvent == nil else { return nil }
        let type = dto.typeMessage.uppercased()
        // `isMessageSystem` alone is not enough: call records carry it too, and
        // must keep their own bubble.
        let isSystem = type == "SYSTEM"
            || (dto.isMessageSystem == true && MessageModelMapper.mapInboundType(type) == .text)
        guard isSystem else { return nil }
        return kind(content: dto.content)
    }

    /// The kind is named in the content, as the history sync reads it.
    static func kind(content: String) -> Kind {
        let content = content.uppercased()
        if content.contains("CONVERSATION_CREATED") || content.contains("CHAT_CREATED") {
            return .conversationCreated
        }
        if content.contains("CONTACT_UNBLOCKED") || content.contains("USER_UNBLOCKED") {
            return .action(.contactUnblocked)
        }
        if content.contains("CONTACT_BLOCKED") || content.contains("USER_BLOCKED") {
            return .action(.contactBlocked)
        }
        if content.contains("MESSAGES_CLEARED") {
            return .action(.messagesCleared)
        }
        if content.contains("ENCRYPTION_ENABLED") {
            // B61 — announced by the server, but messages travel in clear: the
            // app does not repeat the claim to the user.
            return ChatEncryptionClaim.messagesAreEndToEndEncrypted ? .action(.encryptionEnabled) : .unknown
        }
        return .unknown
    }

    /// The checkpoint to show for a record, if it has one.
    static func checkpoint(
        for dto: InboundMessageDTO,
        kind: Kind,
        conversationId: String
    ) -> ChatActionItem? {
        guard case .action(let actionType) = kind else { return nil }
        let name = dto.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatActionItem(
            id: dto.codeMessage,
            conversationId: conversationId,
            actionType: actionType,
            performedBy: dto.senderId,
            targetId: nil,
            metadata: name.isEmpty ? nil : ["performedByName": name],
            timestamp: Date(timeIntervalSince1970: dto.resolvedTimestamp)
        )
    }

    /// A row stored before this rule existed. `.system` in storage is otherwise
    /// only ever a call or a group event, both of which leave their mark in the
    /// content — so this needs no decryption to tell.
    static func isStoredRecord(_ model: MessageModel) -> Bool {
        model.type == .system
            && model.content.groupEventType == nil
            && model.content.callIsVideo == nil
            && model.content.callConnected == nil
    }
}
