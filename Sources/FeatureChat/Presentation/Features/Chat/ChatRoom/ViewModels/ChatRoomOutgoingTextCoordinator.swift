//
//  ChatRoomOutgoingTextCoordinator.swift
//  FeatureChat
//

import Foundation

/// Optimistic text send with background E2EE encryption.
enum ChatRoomOutgoingTextCoordinator {

    struct Handlers {
        let sendLocally: (MessageContent, MessageTypeProps, String) -> String?
        let showError: (String) -> Void
        let patchEncrypted: (String, String) async -> Void
    }

    static func send(
        plaintext: String,
        conversationId: String,
        recipientId: String,
        e2eeCoordinator: ChatRoomE2EECoordinator?,
        handlers: Handlers
    ) {
        let content = MessageContent(text: plaintext)
        guard let codeMessage = handlers.sendLocally(content, .TEXT, "") else {
            handlers.showError(ChatErrorStrings.sendMessageFailed)
            return
        }

        // Only attempt encryption if E2EE coordinator is available
        guard let e2eeCoordinator = e2eeCoordinator else { return }

        Task {
            let outcome = await e2eeCoordinator.encryptOutgoingText(
                plaintext: plaintext,
                codeMessage: codeMessage,
                conversationId: conversationId,
                recipientId: recipientId
            )
            guard case .encrypted(let encrypted) = outcome else { return }
            await handlers.patchEncrypted(encrypted, codeMessage)
        }
    }
}

/// Patches encrypted ciphertext onto an already-persisted optimistic message.
enum ChatRoomEncryptedTextPatcher {

    @MainActor
    static func patch(
        encrypted: String,
        codeMessage: String,
        messages: [MessageDataItem],
        messagesUseCases: MessagesUseCasesProtocol
    ) async -> [MessageDataItem] {
        var messages = messages
        guard let index = messages.firstIndex(where: { $0.codeMessage == codeMessage }) else { return messages }
        var updated = messages[index]
        updated.message.text = encrypted
        try? await messagesUseCases.updateMessages.execute(message: updated)
        messages[index] = updated
        return messages
    }
}
