//
//  ChatRoomInitialLoadCoordinator.swift
//  FeatureChat
//

import Foundation

/// Bootstraps the first message page and decrypts E2EE text in the background.
enum ChatRoomInitialLoadCoordinator {

    static func bootstrap(
        conversationId: String,
        discussionsUseCases: DiscussionUseCasesProtocol,
        e2eeCoordinator: ChatRoomE2EECoordinator?,
        onFirstPaint: @MainActor @escaping (ChatRoomPaginationCoordinator.PageResult) -> Void,
        onDecrypted: @MainActor @escaping ([MessageDataItem]) -> Void,
        postLoad: () async -> Void
    ) async {
        do {
            let result = try await ChatRoomPaginationCoordinator.loadInitial(
                conversationId: conversationId,
                pageSize: ChatRoomPaginationCoordinator.pageSize(),
                discussionsUseCases: discussionsUseCases
            )

            await onFirstPaint(result)
            await postLoad()

            if let e2eeCoordinator = e2eeCoordinator {
                let decrypted = await e2eeCoordinator.decryptBatch(result.messages, conversationId: conversationId)
                await onDecrypted(ChatRoomMessagesStore.merged(existing: [], incoming: decrypted))
            } else {
                await onDecrypted(ChatRoomMessagesStore.merged(existing: [], incoming: result.messages))
            }
        } catch {
            #if DEBUG
            print("Error loading messages: \(error)")
            #endif
        }
    }
}
