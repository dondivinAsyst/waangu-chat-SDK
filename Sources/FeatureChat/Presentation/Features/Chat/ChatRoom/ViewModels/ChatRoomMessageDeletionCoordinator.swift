//
//  ChatRoomMessageDeletionCoordinator.swift
//  FeatureChat
//

import Foundation

/// Soft-deletes messages locally and cleans up on-disk media.
enum ChatRoomMessageDeletionCoordinator {

    static func delete(
        _ message: MessageDataItem,
        forEveryone: Bool = false,
        messagesUseCases: MessagesUseCasesProtocol
    ) async throws {
        try await messagesUseCases.deleteMessages.execute(
            messageId: message.codeMessage,
            forEveryone: forEveryone
        )
        ChatRoomMessageMediaCleanup.deleteMediaFiles(for: message)
    }

    static func notifyDiscussionsShouldRefresh() {
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }

    /// Deletes each message; skips remote notify for unsent/failed (local-only).
    static func deleteBatch(
        _ targets: [MessageDataItem],
        onlyMe _: Bool,
        deleteOne: (MessageDataItem) async throws -> Void,
        notifyRemote: (MessageDataItem) async -> Void
    ) async -> String? {
        for message in targets {
            do {
                try await deleteOne(message)
                let isUnsent = message.status == .PENDING || message.status == .FAILED
                if !isUnsent {
                    await notifyRemote(message)
                }
            } catch {
                #if DEBUG
                print("Error deleting message: \(error)")
                #endif
                return ChatErrorStrings.deleteMessageFailed
            }
        }
        return nil
    }
}

