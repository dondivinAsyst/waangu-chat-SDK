import Foundation
import WaanguCoreKit
import UIKit

/// Builds outgoing chat messages and prepares on-disk media before send.
enum OutgoingMessageBuilder {

    enum PrepareResult: Sendable {
        case ready(message: MessageDataItem, code: String)
        case failed(String)
    }

    static func newCode() -> String {
        UUID().uuidString.lowercased()
    }

    static func replyFrom(_ replyMessage: MessageRow?) -> MessageReply? {
        guard let replyToMes = replyMessage else { return nil }
        switch replyToMes {
        case .mediaGroup(_, let media):
            return MessageReply.message(media.first)
        case .message(let msg):
            return MessageReply.message(msg)
        case .checkpoint, .encryptionBanner, .groupIntro:
            return nil
        }
    }

    /// Builds a reply snapshot from a status segment (same `replyTo*` fields as chat replies).
    static func replyFrom(status item: StatusItem, ownerName: String?) -> MessageReply {
        StatusReplySnapshotBuilder.buildReply(from: item, ownerName: ownerName)
    }

    static func buildOutgoingMessage(
        content: MessageContent,
        type: MessageTypeProps,
        groupId: String?,
        reply: MessageReply?,
        code: String? = nil,
        receiverId: String = "",
        forwarded: Bool = false,
        viewOnce: Bool = false
    ) -> MessageDataItem {
        let messageCode = code ?? newCode()
        return MessageDataItem(
            codeMessage: messageCode,
            senderId: CurrentSessionInfo.shared.currentUid,
            senderAvatar: CurrentSessionInfo.shared.userProfile,
            senderPhone: CurrentSessionInfo.shared.userPhoneNumber,
            senderName: CurrentSessionInfo.shared.userName,
            receiverId: receiverId,
            groupId: groupId,
            typeMessage: type,
            message: content,
            reply: reply,
            forwarded: forwarded,
            status: .PENDING,
            isMoney: false,
            isViewOnce: viewOnce,
            createdAt: Date()
        )
    }

    static func validateAndCacheImage(content: MessageContent, code: String) -> String? {
        if let image = content.UIimage {
            ChatRoomMediaPersistence.saveCachedMedia(
                url: content.image ?? "",
                key: code,
                type: .image,
                image: image
            )
            return nil
        }

        guard let imageUrlString = content.image, !imageUrlString.isEmpty else {
            return ChatErrorStrings.sendImageInvalidPath
        }

        guard let url = resolveLocalURL(imageUrlString),
              url.scheme == "file" || url.scheme == nil,
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }

        ChatRoomMediaPersistence.saveCachedMedia(
            url: imageUrlString,
            key: code,
            type: .image,
            image: image
        )
        return nil
    }

    static func prepareAudio(
        content: MessageContent,
        baseMessage: MessageDataItem
    ) -> PrepareResult {
        guard let audioUrlString = content.audio, !audioUrlString.isEmpty else {
            return .failed(ChatErrorStrings.sendAudioInvalidPath)
        }

        guard let url = resolveLocalURL(audioUrlString) else {
            return .failed(String(format: ChatErrorStrings.sendAudioBadURL, audioUrlString))
        }

        guard let savedURL = DiskMediaManager.shared.saveAudioToDisk(
            from: url,
            fileName: baseMessage.codeMessage,
            pathName: .CHAT
        ) else {
            return .failed(ChatErrorStrings.sendAudioSaveFailed)
        }

        var updatedContent = content
        updatedContent.audio = savedURL.path
        updatedContent.fileName = "\(baseMessage.codeMessage).\(url.pathExtension)"

        let updatedMessage = MessageDataItem(
            codeMessage: baseMessage.codeMessage,
            senderId: baseMessage.senderId,
            senderAvatar: baseMessage.senderAvatar,
            senderPhone: baseMessage.senderPhone,
            senderName: baseMessage.senderName,
            receiverId: baseMessage.receiverId,
            groupId: baseMessage.groupId,
            typeMessage: baseMessage.typeMessage,
            message: updatedContent,
            reply: baseMessage.reply,
            forwarded: baseMessage.forwarded,
            status: baseMessage.status,
            isMoney: baseMessage.isMoney,
            isViewOnce: baseMessage.isViewOnce,
            createdAt: baseMessage.createdAt
        )

        return .ready(message: updatedMessage, code: baseMessage.codeMessage)
    }

    private static func resolveLocalURL(_ path: String) -> URL? {
        if path.hasPrefix("file://") {
            return URL(string: path)
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(string: path)
    }

    /// Media with a local file must upload before MQTT/outbox publish.
    static func requiresUploadBeforePublish(_ message: MessageDataItem) -> Bool {
        message.message.shouldUploadDownload
    }
}

enum MarkDeliveredPublisher {

    static func publish(
        codeMessage: String,
        conversationId: String,
        userId: String,
        deliveredAt: Int64? = nil,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !codeMessage.isEmpty, !conversationId.isEmpty, !userId.isEmpty else { return }

        let dto = OutboundMarkDeliveredDTO(
            codeMessage: codeMessage,
            conversationId: conversationId,
            userId: userId,
            deliveredAt: deliveredAt ?? Int64(Date().timeIntervalSince1970 * 1_000)
        )

        try? await outbox.enqueue(ChatOutboxItem.markDelivered(dto))
        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.In.markDelivered,
            qos: .atLeastOnce,
            priority: .normal
        )
    }
}

enum MarkAsReadPublisher {

    static func publish(
        codeMessage: String,
        userId: String,
        conversationId: String,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !codeMessage.isEmpty, !userId.isEmpty else { return }

        let dto = OutboundMarkAsReadDTO(
            codeMessage: codeMessage,
            userId: userId
        )

        try? await outbox.enqueue(
            ChatOutboxItem.markAsRead(dto, conversationId: conversationId)
        )
        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.In.markAsRead,
            qos: .atLeastOnce,
            priority: .normal
        )
    }
}

enum DeleteMessagePublisher {

    static func publish(
        codeMessage: String,
        conversationId: String,
        forEveryone: Bool,
        senderId: String,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !codeMessage.isEmpty, !conversationId.isEmpty, !senderId.isEmpty else { return }

        let dto = OutboundMessageDeleteDTO(
            senderId: senderId,
            conversationId: conversationId,
            codeMessage: codeMessage,
            forEveryone: forEveryone
        )

        try? await outbox.enqueue(ChatOutboxItem.deleteMessage(dto))
        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.In.deleteMessage,
            qos: .atLeastOnce,
            priority: .high
        )
    }
}

enum ModifyMessagePublisher {

    static func publish(
        codeMessage: String,
        conversationId: String,
        content: String,
        status: String,
        senderId: String,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !codeMessage.isEmpty,
              !conversationId.isEmpty,
              !senderId.isEmpty,
              !content.isEmpty else { return }

        let dto = OutboundModifyMessageDTO(
            sessionId: CurrentSessionInfo.shared.sessionId,
            senderId: senderId,
            conversationId: conversationId,
            codeMessage: codeMessage,
            content: content,
            status: status
        )

        try? await outbox.enqueue(ChatOutboxItem.modifyMessage(dto))
        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.In.modifyMessage,
            qos: .atLeastOnce,
            priority: .high
        )
    }
}

enum ReactionMessagePublisher {

    static func publish(
        codeMessage: String,
        conversationId: String,
        reaction: String,
        userId: String,
        removing: Bool,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !codeMessage.isEmpty,
              !conversationId.isEmpty,
              !userId.isEmpty else { return }

        let sessionId = CurrentSessionInfo.shared.sessionId

        if removing {
            let dto = OutboundRemoveReactionDTO(
                sessionId: sessionId,
                userId: userId,
                conversationId: conversationId,
                codeMessage: codeMessage
            )
            try? await outbox.enqueue(ChatOutboxItem.removeReaction(dto))
            try? await realtime.publish(
                dto,
                to: ChatMQTTTopics.In.removeReaction,
                qos: .atLeastOnce,
                priority: .high
            )
            return
        }

        guard !reaction.isEmpty else { return }

        let dto = OutboundReactMessageDTO(
            sessionId: sessionId,
            userId: userId,
            conversationId: conversationId,
            codeMessage: codeMessage,
            reaction: reaction
        )

        try? await outbox.enqueue(ChatOutboxItem.reactMessage(dto))
        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.In.reactMessage,
            qos: .atLeastOnce,
            priority: .high
        )
    }
}

enum PollMessagePublisher {

    /// Publishes the voter's whole selection for a poll message.
    ///
    /// An empty `optionIds` is a retraction and must still be sent — it is the
    /// only way the server learns the vote was withdrawn — so unlike the other
    /// publishers here, emptiness is not a reason to bail out.
    ///
    /// Enqueued before it is published, like every other mutation of a stored
    /// message, so a vote cast with no connection is replayed rather than lost.
    static func publishVote(
        codeMessage: String,
        conversationId: String,
        optionIds: [String],
        userId: String,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) async {
        guard !codeMessage.isEmpty,
              !conversationId.isEmpty,
              !userId.isEmpty else { return }

        let session = CurrentSessionInfo.shared
        let dto = OutboundVotePollDTO(
            codeMessage: codeMessage,
            conversationId: conversationId,
            userId: userId,
            selectedOptions: optionIds,
            tenantId: session.tenantId.isEmpty ? nil : session.tenantId,
            country: session.country.isEmpty ? nil : session.country
        )

        try? await outbox.enqueue(ChatOutboxItem.votePoll(dto))
        try? await realtime.publish(
            dto,
            to: ChatMQTTTopics.In.votePoll,
            qos: .atLeastOnce,
            priority: .high
        )
    }
}

enum OutgoingMessagePublisher {

    static func publish(
        message: MessageDataItem,
        conversationId: String,
        recipientId: String?,
        outbox: any ChatOutboxEnqueuing,
        realtime: any RealtimeClientProtocol
    ) async {
        let normalized = OutboundMessageFieldNormalizer.ensuringSenderFields(message)
        let dto = OutboundMessageDTOBuilder.build(
            from: normalized,
            conversationId: conversationId,
            recipientId: recipientId
                ?? (normalized.receiverId.isEmpty ? nil : normalized.receiverId)
        )
        try? await outbox.enqueue(ChatOutboxItem.sendMessage(dto))
        #if DEBUG
        print("[OutgoingMessagePublisher] dto senderPhone=\(dto.senderPhone) type=\(dto.typeMessage)")
        #endif
        try? await realtime.publish(
            dto.withFreshNonce(),
            to: ChatMQTTTopics.In.sendMessage,
            qos: .atLeastOnce,
            priority: .high
        )
    }
}

/// Fills any empty outbound identity fields from the current session before MQTT/outbox publish.
enum OutboundMessageFieldNormalizer {

    static func ensuringSenderFields(_ message: MessageDataItem) -> MessageDataItem {
        var updated = message
        let session = CurrentSessionInfo.shared

        if updated.senderId.isEmpty {
            updated.senderId = session.currentUid
        }
        if updated.senderPhone.isEmpty {
            updated.senderPhone = session.userPhoneNumber
        }
        if updated.senderName.isEmpty {
            updated.senderName = session.userName
        }
        if updated.senderAvatar == nil || updated.senderAvatar?.isEmpty == true {
            let profile = session.userProfile
            updated.senderAvatar = profile.isEmpty ? nil : profile
        }
        return updated
    }
}

enum OutboundMessageDTOBuilder {

    static func build(
        from message: MessageDataItem,
        conversationId: String,
        recipientId: String?
    ) -> OutboundMessageDTO {
        let normalized = OutboundMessageFieldNormalizer.ensuringSenderFields(message)
        let resolvedReceiver = recipientId
            ?? (normalized.receiverId.isEmpty ? nil : normalized.receiverId)
            ?? ""

        let session = CurrentSessionInfo.shared
        return OutboundMessageDTO(
            sessionId: session.sessionId,
            senderId: normalized.senderId,
            senderName: normalized.senderName,
            senderPhone: normalized.senderPhone,
            senderAvatar: normalized.senderAvatar,
            receiverId: resolvedReceiver,
            groupId: normalized.groupId.flatMap { $0.isEmpty ? nil : $0 },
            conversationId: conversationId,
            codeMessage: normalized.codeMessage,
            content: MessageContentWireCodec.encode(from: normalized),
            typeMessage: normalized.typeMessage.rawValue,
            status: normalized.status.rawValue,
            forwarded: normalized.forwarded,
            viewOnce: normalized.isViewOnce,
            isMoney: normalized.isMoney,
            transactionId: normalized.transactionId,
            isMessageSystem: false,
            tenantId: session.tenantId.isEmpty ? nil : session.tenantId,
            country: session.country.isEmpty ? nil : session.country
        )
    }
}
