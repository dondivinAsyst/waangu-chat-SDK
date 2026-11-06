//
//  ConversationMessageComposer.swift
//  FeatureChat
//

import Foundation
import UIKit
import WaanguCoreKit

/// Turns something the user picked into a message on its way out.
///
/// Every room composes the same way — validate, build a `MessageContent`, hand it
/// to `sendMessage` — and only the surrounding context differs: a chat has a
/// peer and a reply, a broadcast has neither. That context is supplied by a
/// closure, so both rooms share this rather than each keeping its own copy of
/// the same six builders.
///
/// Not a use case: the building blocks it calls (`ChatRoomMediaSendCoordinator`,
/// `ChatRoomDocumentSender`, `ChatRoomVoiceMessageFlow`) are presentation-side
/// helpers, and the one piece of domain work — publishing — is delegated to
/// `SendMessageUseCaseProtocol` untouched.
@MainActor
final class ConversationMessageComposer {

    /// What the room knows and this does not: who is on the other side, and what
    /// is being replied to. A broadcast supplies none of it.
    struct Context {
        let receiver: UserRoom?
        let recipientId: String?
        let reply: MessageReply?

        static let broadcast = Context(receiver: nil, recipientId: nil, reply: nil)
    }

    private let conversationId: String
    /// Direct, group or channel — stated once, carried all the way to the store.
    private let kind: ConversationKind
    private let sendMessage: SendMessageUseCaseProtocol
    private let context: () -> Context
    private let onError: (String) -> Void
    /// Called after a successful send, so the room can clear its reply banner.
    private let onSent: () -> Void

    init(
        conversationId: String,
        kind: ConversationKind,
        sendMessage: SendMessageUseCaseProtocol,
        context: @escaping () -> Context = { .broadcast },
        onError: @escaping (String) -> Void,
        onSent: @escaping () -> Void = {}
    ) {
        self.conversationId = conversationId
        self.kind = kind
        self.sendMessage = sendMessage
        self.context = context
        self.onError = onError
        self.onSent = onSent
    }

    // MARK: - The one way out

    /// Publishes any content. Everything below funnels through here.
    @discardableResult
    func send(
        _ content: MessageContent,
        type: MessageTypeProps,
        messageCode: String? = nil,
        viewOnce: Bool = false
    ) -> String? {
        let code = messageCode ?? OutgoingMessageBuilder.newCode()

        if type == .IMAGE,
           let error = OutgoingMessageBuilder.validateAndCacheImage(content: content, code: code) {
            onError(error)
            return nil
        }

        let context = context()
        Task {
            let request = SendMessageRequest(
                content: content,
                type: type,
                conversationId: conversationId,
                receiver: context.receiver,
                kind: kind,
                reply: context.reply,
                recipientId: context.recipientId,
                messageCode: code,
                viewOnce: viewOnce
            )

            if await sendMessage.execute(request) == nil {
                onError(ChatErrorStrings.sendMessageFailed)
            } else {
                onSent()
            }
        }

        return code
    }

    // MARK: - Media

    /// A picked or captured payload, with its video cached for the upload that
    /// follows. A video note goes the same way as a video; only its type differs.
    @discardableResult
    func sendMedia(
        _ payload: MediaPayload,
        caption: String?,
        batchId: String? = nil,
        asVideoNote: Bool = false
    ) -> String? {
        let isVideo = payload.mediaType == .video
        let content = ChatRoomMediaSendCoordinator.makeContent(
            from: payload,
            caption: caption,
            batchId: batchId
        )
        let videoType: MessageTypeProps = asVideoNote ? .VIDEO_NOTE : .VIDEO

        guard let code = send(content, type: isVideo ? videoType : .IMAGE) else {
            onError(isVideo ? ChatErrorStrings.sendVideoFailed : ChatErrorStrings.sendImageFailed)
            return nil
        }

        if isVideo, !ChatRoomMediaSendCoordinator.cacheSentVideo(media: payload, code: code) {
            // A failed cache here is what later surfaces as an upload dying with
            // "Local file not found", so it is reported where it happens.
            onError(ChatErrorStrings.sendVideoFailed)
        }

        return code
    }

    /// Gallery items, whose thumbnails are generated before each send.
    func sendGalleryMedia(caption: String?, selectedMedia: [GalleryMedia]) {
        ChatRoomGallerySendCoordinator.sendMediaItems(
            caption: caption,
            selectedMedia: selectedMedia,
            handlers: ChatRoomGallerySendCoordinator.Handlers(
                sendMedia: { [weak self] payload, caption, batchId in
                    self?.sendMedia(payload, caption: caption, batchId: batchId)
                }
            )
        )
    }

    func sendCapturedMedia(_ captured: CapturedCameraMedia, caption: String?) {
        let captionText = caption ?? ""

        switch captured {
        case .image(let image, let jpegData):
            sendMedia(
                ChatCameraCapturedMediaSender.makeImagePayload(
                    image: image,
                    caption: captionText,
                    jpegData: jpegData
                ),
                caption: caption
            )
        case .video(let url):
            sendMedia(
                ChatCameraCapturedMediaSender.makeVideoPayload(url: url, caption: captionText),
                caption: caption
            )
        case .videoNote(let url):
            sendMedia(
                ChatCameraCapturedMediaSender.makeVideoPayload(url: url, caption: captionText),
                caption: caption,
                asVideoNote: true
            )
        }
    }

    func sendEditedMedia(_ result: EditedMediaResult, caption: String?) {
        switch result {
        case .uneditedGallery(let media):
            sendGalleryMedia(caption: caption, selectedMedia: [media])
        case .exportedImage(let image, let jpegData):
            sendCapturedMedia(.image(image, jpegData: jpegData), caption: caption)
        case .exportedVideo(let url):
            sendCapturedMedia(.video(url), caption: caption)
        }
    }

    // MARK: - Documents, contacts, location, polls

    func sendDocument(fileURL: URL) {
        ChatRoomDocumentSender.send(
            fileURL: fileURL,
            handlers: ChatRoomDocumentSender.Handlers(
                sendMessage: { [weak self] content, type, _, messageCode in
                    self?.send(content, type: type, messageCode: messageCode)
                },
                showError: { [weak self] message in
                    self?.onError(message)
                }
            )
        )
    }

    func sendContacts(_ contacts: [ContactItem]) {
        guard !contacts.isEmpty else { return }
        send(MessageContent(contact: contacts), type: .CONTACT)
    }

    @discardableResult
    func sendLocation(_ location: ChatLocationItem) -> String? {
        send(MessageContent(location: location), type: .LOCATION)
    }

    /// - Returns: `false` when the poll is not worth sending, so the caller can
    ///   say so in its own words.
    @discardableResult
    func sendPoll(question: String, options: [String], allowsMultipleAnswers: Bool) -> Bool {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOptions = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedQuestion.isEmpty, trimmedOptions.count >= 2 else { return false }

        var content = MessageContent()
        content.poll = PollContent(
            question: trimmedQuestion,
            options: trimmedOptions.map { PollOption(text: $0) },
            isMultipleChoice: allowsMultipleAnswers
        )
        send(content, type: .POLL)
        return true
    }

    // MARK: - Voice

    /// Sends a finished recording, holding the attachment the flow builds.
    func sendVoice(
        result: VoiceRecordingResult?,
        attachments: ChatRoomVoiceAttachmentStore
    ) async {
        await ChatRoomVoiceMessageFlow.stopAndSend(
            result: result,
            handlers: ChatRoomVoiceMessageFlow.SendHandlers(
                appendAttachment: { attachments.append($0) },
                firstAudioAttachment: { attachments.firstAudio() },
                sendMessage: { [weak self] content, type, _ in
                    self?.send(content, type: type)
                },
                showError: { [weak self] message in
                    self?.onError(message)
                },
                clearAttachments: { attachments.clear() }
            )
        )
    }
}

/// Holds a recording between "stopped" and "sent".
///
/// A tiny class rather than an array on each room: the voice flow reads it back
/// through closures, and both rooms need the same three operations.
@MainActor
final class ChatRoomVoiceAttachmentStore {

    private var attachments: [MediaAttachment] = []

    func append(_ attachment: MediaAttachment) {
        attachments.append(attachment)
    }

    func firstAudio() -> MediaAttachment? {
        attachments.first { $0.fileURL != nil }
    }

    func clear() {
        attachments.removeAll()
    }
}
