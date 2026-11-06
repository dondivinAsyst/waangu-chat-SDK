//
//  ChatRoomAttachmentPersistence.swift
//  FeatureChat
//

import Foundation

enum ChatRoomAttachmentField {
    case audio
    case file
}

/// Patches on-disk file paths onto sent messages.
enum ChatRoomAttachmentPersistence {

    static func patchMessage(
        sourceURL: URL,
        code: String,
        field: ChatRoomAttachmentField,
        messages: inout [MessageDataItem],
        messagesUseCases: MessagesUseCasesProtocol,
        onUpdated: () -> Void
    ) {
        guard let persistedPath = ChatRoomMediaPersistence.persistFile(from: sourceURL, code: code) else { return }
        guard let index = messages.firstIndex(where: { $0.codeMessage == code }) else { return }

        var updated = messages[index]
        switch field {
        case .audio: updated.message.audio = persistedPath
        case .file: updated.message.file = persistedPath
        }

        messages[index] = updated
        onUpdated()
        Task { try? await messagesUseCases.updateMessages.execute(message: updated) }
    }
}
