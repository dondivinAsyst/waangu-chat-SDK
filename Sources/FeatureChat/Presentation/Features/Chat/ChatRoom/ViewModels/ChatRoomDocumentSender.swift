//
//  ChatRoomDocumentSender.swift
//  FeatureChat
//

import Foundation

/// Sends file attachments picked from the Document tab as `DOCUMENT` messages.
enum ChatRoomDocumentSender {

    struct Handlers {
        let sendMessage: (MessageContent, MessageTypeProps, String, String?) -> String?
        let showError: (String) -> Void
    }

    static func send(fileURL: URL, handlers: Handlers) {
        let fileName = fileURL.lastPathComponent.removingPercentEncoding ?? fileURL.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        let ext = fileURL.pathExtension.lowercased()
        let mimeType = ChatRoomMediaPersistence.mimeType(for: ext)

        Task { @MainActor in
            let code = OutgoingMessageBuilder.newCode()
            let persistedPath = ChatRoomMediaPersistence.persistFile(from: fileURL, code: code)
            let filePath = persistedPath ?? fileURL.absoluteString
            let content = MessageContent(
                shouldUploadDownload: true,
                shouldRetry: false,
                file: filePath,
                fileName: fileName,
                size: fileSize,
                mimeType: mimeType
            )
            guard handlers.sendMessage(content, .DOCUMENT, "", code) != nil else {
                handlers.showError(ChatErrorStrings.sendDocumentFailed)
                return
            }
        }
    }
}
