//
//  ChatRoomVoiceMessageFlow.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

/// Voice recording → attachment pipeline for chat room sends.
enum ChatRoomVoiceMessageFlow {

    static func makeAttachment(from result: VoiceRecordingResult) -> MediaAttachment {
        MediaAttachment(
            id: UUID().uuidString,
            type: .audio(result.url, result.duration, result.waveform)
        )
    }

    static func makeMessageContent(from attachment: MediaAttachment) -> MessageContent? {
        guard let audioURL = attachment.fileURL else { return nil }
        var content = MessageContent()
        content.audio = audioURL.path
        content.audioDuration = attachment.audioDuration
        content.waveform = attachment.waveform
        content.shouldUploadDownload = true
        content.shouldRetry = false
        // fileName is required by the upload guard in BubbleVoiceView
        content.fileName = audioURL.lastPathComponent
        content.mimeType = "audio/ogg"
        return content
    }

    struct SendHandlers {
        let appendAttachment: @MainActor (MediaAttachment) -> Void
        let firstAudioAttachment: @MainActor () -> MediaAttachment?
        let sendMessage: @MainActor (MessageContent, MessageTypeProps, String) -> String?
        let showError: @MainActor (String) -> Void
        let clearAttachments: @MainActor () -> Void
    }

    /// Stops recording, builds the attachment, and sends the voice message.
    static func stopAndSend(result: VoiceRecordingResult?, handlers: SendHandlers) async {
        guard let result else { return }

        let attachment = makeAttachment(from: result)
        await MainActor.run { handlers.appendAttachment(attachment) }

        let audioAttachment = await MainActor.run { handlers.firstAudioAttachment() }
        guard let audioAttachment,
              let content = makeMessageContent(from: audioAttachment) else { return }

        await MainActor.run {
            guard handlers.sendMessage(content, .VOICE, "") != nil else {
                handlers.showError(ChatErrorStrings.sendVoiceFailed)
                return
            }
            handlers.clearAttachments()
        }
    }
}
