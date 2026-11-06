//
//  MessageForwardingService.swift
//  FeatureChat
//

import Foundation
import UIKit

/// Sends messages on to somewhere else.
///
/// Forwarding is the same work wherever it starts — rebuild each message as a
/// payload, re-read its media off disk, send it to the target — and only the
/// room it starts from differs. Extracted for the same reason
/// `ConversationMessageComposer` was: a channel post is forwarded exactly like a
/// chat message, and neither room should own the other's copy.
@MainActor
final class MessageForwardingService {

    private let sendMessage: SendMessageUseCaseProtocol

    /// Media is re-read from the chat disk cache, which is where every room's
    /// attachments already live.
    private let mediaAccess = ChatRoomMessageForwarder.MediaAccess(
        cachedImage: { DiskMediaManager.shared.loadImageFromDisk(fileName: $0, pathName: .CHAT) },
        cachedMediaURL: { DiskMediaManager.shared.loadVideoFromDisk(fileName: $0, pathName: .CHAT) }
    )

    init(sendMessage: SendMessageUseCaseProtocol) {
        self.sendMessage = sendMessage
    }

    /// Forwards to one target, with an optional note of the sender's own.
    ///
    /// The note is sent as a plain message, not a forward: it is the sender's
    /// words, so it must not carry the "Forwarded" label.
    func forward(
        _ messages: [MessageDataItem],
        to target: ForwardTarget,
        caption: String?
    ) async {
        guard let conversationId = target.conversationId, !conversationId.isEmpty,
              let receiver = target.receiver
        else { return }

        let kind: ConversationKind = target.isGroup ? .group : .direct

        for payload in ChatRoomMessageForwarder.payloads(for: messages, mediaAccess: mediaAccess) {
            _ = await sendMessage.execute(
                SendMessageRequest(
                    content: payload.content,
                    type: payload.type,
                    conversationId: conversationId,
                    receiver: receiver,
                    kind: kind,
                    recipientId: receiver.userId,
                    messageCode: payload.code,
                    forwarded: true
                )
            )
        }

        if let caption, !caption.isEmpty {
            _ = await sendMessage.execute(
                SendMessageRequest(
                    content: MessageContent(text: caption),
                    type: .TEXT,
                    conversationId: conversationId,
                    receiver: receiver,
                    kind: kind,
                    recipientId: receiver.userId
                )
            )
        }
    }

    /// Forwards to several targets at once.
    func forward(
        _ messages: [MessageDataItem],
        to targets: [ForwardTarget],
        caption: String?
    ) async {
        for target in targets where !target.isStatus {
            await forward(messages, to: target, caption: caption)
        }
    }
}
