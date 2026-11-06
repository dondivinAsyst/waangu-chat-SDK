//
//  GRDBMessageDataSource.swift
//  FeatureChat
//
//  Adapted to the new MessageModel schema:
//  – UUID typed IDs
//  – MessageContentModel embedded in MessageModel.content (no separate table)
//  – deliveryStatus: MessageDeliveryStatusModel instead of raw String
//  – conversationId replaces discussionId
//

import Foundation
import WaanguCoreKit

final class GRDBMessageDataSource: LocalMessageDataSourceProtocol {

    private let store: any DatabaseRepositoryProtocol
    private let fieldEncryptionService: any FieldEncryptionServiceProtocol

    init(
        store: any DatabaseRepositoryProtocol,
        fieldEncryptionService: any FieldEncryptionServiceProtocol
    ) {
        self.store = store
        self.fieldEncryptionService = fieldEncryptionService
    }

    // MARK: - Fetch

    func fetchMessages(_ conversationId: String) async throws -> [MessageDataItem] {
        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversationId)),
            sort: [SortSpec("timestamp", ascending: true)]
        )
        let models = try await store.fetch(MessageModel.self, query: query)
        let items = MessageTimelineVisibility.filterVisible(models)
            .map { MessageModelMapper.toDomain($0, fieldCrypto: fieldEncryptionService) }
        return try await attachReactions(to: items)
    }

    func fetchRecentSentDocuments(
        conversationId: String,
        senderId: String,
        limit: Int
    ) async throws -> [MessageDataItem] {
        let query = QuerySpec(
            filter: FilterSpec(
                "conversation_id == %@ AND type == %@ AND sender_id == %@ AND is_deleted == %@",
                .string(conversationId),
                .string(MessageTypeModel.document.rawValue),
                .string(senderId),
                .bool(false)
            ),
            sort: [SortSpec("timestamp", ascending: false)],
            limit: max(limit, 1)
        )

        let models = try await store.fetch(MessageModel.self, query: query)
        let items = models
            .filter { $0.deliveryStatus != .pending && $0.deliveryStatus != .failed }
            .map { MessageModelMapper.toDomain($0, fieldCrypto: fieldEncryptionService) }
        return try await attachReactions(to: items)
    }

    func observeMessages(_ conversationId: String) -> AsyncStream<Result<[MessageDataItem], DatabaseError>> {
        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversationId)),
            sort: [SortSpec("timestamp", ascending: true)]
        )
        let fieldCrypto = fieldEncryptionService
        let store = store
        return AsyncStream { continuation in
            let task = Task {
                let stream = await store.observe(MessageModel.self, query: query)
                for await result in stream {
                    switch result {
                    case .success(let models):
                        let mapped = MessageTimelineVisibility.filterVisible(models)
                            .map { MessageModelMapper.toDomain($0, fieldCrypto: fieldCrypto) }
                        let items = (try? await Self.attachReactions(
                            to: mapped,
                            store: store
                        )) ?? mapped
                        continuation.yield(.success(items))
                    case .failure(let error):
                        continuation.yield(.failure(error))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func countMediaMessages(groupId: String) async -> Int {
        let mediaTypes: [String] = [
            MessageTypeModel.image.rawValue,
            MessageTypeModel.video.rawValue,
            MessageTypeModel.videoNote.rawValue,
            MessageTypeModel.document.rawValue,
            MessageTypeModel.audio.rawValue,
            MessageTypeModel.voice.rawValue,
        ]
        var total = 0
        for typeRaw in mediaTypes {
            let query = QuerySpec(
                filter: FilterSpec(
                    "conversation_id == %@ AND type == %@ AND is_deleted == %@",
                    .string(groupId),
                    .string(typeRaw),
                    .bool(false)
                )
            )
            let count = (try? await store.count(MessageModel.self, query: query)) ?? 0
            total += count
        }
        return total
    }

    // MARK: - Update

    func updateMessage(_ message: MessageDataItem) async throws {
        guard let existing = try await fetchMessageModel(id: message.codeMessage) else {
            throw DatabaseError.notFound(
                id: message.codeMessage,
                type: String(describing: MessageModel.self),
                namespace: MessageModel.namespace
            )
        }

        let deliveryStatus = MessageModelMapper.mapToDeliveryStatus(message.status)
        let content = MessageModelMapper.buildContent(from: message, fieldCrypto: fieldEncryptionService)
        let previousText = existing.content.text.map { fieldEncryptionService.decrypt($0) } ?? ""
        let textChanged = previousText != message.message.text
        let isEdited = existing.isEdited || textChanged
        let editedAt = textChanged ? Date() : existing.editedAt

        let updated = MessageModel(
            id: existing.id,
            conversationId: existing.conversationId,
            senderId: existing.senderId,
            senderName: existing.senderName,
            type: existing.type,
            content: content,
            timestamp: existing.timestamp,
            deliveryStatus: deliveryStatus,
            replyToMessageId: existing.replyToMessageId,
            replyToSenderName: existing.replyToSenderName,
            replyToMessageType: existing.replyToMessageType,
            replyToMessagePreview: existing.replyToMessagePreview,
            replyToThumbnailURL: existing.replyToThumbnailURL,
            replyToIsDeleted: existing.replyToIsDeleted,
            isForwarded: message.forwarded,
            forwardCount: existing.forwardCount,
            isEdited: isEdited,
            editedAt: editedAt,
            isDeleted: message.isDeleted,
            deletedAt: message.isDeleted ? (existing.deletedAt ?? Date()) : nil,
            isDeletedForAll: existing.isDeletedForAll,
            isViewOnce: existing.isViewOnce,
            mentionedUserIds: existing.mentionedUserIds,
            isStarred: existing.isStarred,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        try await store.save(updated)

        if textChanged {
            try await refreshConversationLastMessagePreview(conversationId: existing.conversationId)
            NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
        }
    }

    // MARK: - Reactions

    func applyReaction(
        messageId: String,
        userId: String,
        userName: String,
        emoji: String,
        removing: Bool
    ) async throws -> [ReactionItem] {
        let query = QuerySpec(
            filter: FilterSpec(
                "message_id == %@ AND user_id == %@",
                .string(messageId),
                .string(userId)
            ),
            limit: 1
        )

        if removing {
            if let existing = try await store.fetch(MessageReactionModel.self, query: query).first {
                try await store.delete(MessageReactionModel.self, id: existing.id)
            }
        } else if var existing = try await store.fetch(MessageReactionModel.self, query: query).first {
            existing.emoji = emoji
            existing.userName = userName
            existing.updatedAt = Date()
            try await store.save(existing)
        } else {
            let model = MessageReactionModel(
                messageId: messageId,
                userId: userId,
                userName: userName,
                emoji: emoji
            )
            try await store.save(model)
        }

        // Touch the parent message so `observeMessages` (MessageModel observation) re-emits
        // and the active chat room refreshes reactions live — same path as new messages.
        try await touchMessageForReactionObservation(messageId: messageId)

        return try await fetchReactions(messageId: messageId)
    }

    /// Bumps `MessageModel.updatedAt` so ValueObservation on messages fires after reaction writes.
    private func touchMessageForReactionObservation(messageId: String) async throws {
        guard var message = try await fetchMessageModel(id: messageId) else { return }
        message.updatedAt = Date()
        try await store.save(message)
    }

    // MARK: - Delete (soft)

    func deleteMessage(messageId: String) async throws {
        try await deleteMessage(messageId: messageId, forEveryone: false)
    }

    func deleteMessage(messageId: String, forEveryone: Bool) async throws {
        guard var existing = try await fetchMessageModel(id: messageId) else {
            throw DatabaseError.notFound(
                id: messageId,
                type: String(describing: MessageModel.self),
                namespace: MessageModel.namespace
            )
        }

        existing.isDeleted = true
        existing.deletedAt = Date()
        existing.searchText = nil   // legacy rows: no plaintext survives a delete
        existing.updatedAt = Date()
        if forEveryone {
            existing.isDeletedForAll = true
            // Wait for delete ACK — bubble shows pending clock only.
            existing.deliveryStatus = .pending
        }
        try await store.save(existing)
        try await refreshConversationLastMessagePreview(conversationId: existing.conversationId)
    }

    // MARK: - Private helpers

    private func fetchMessageModel(id: String) async throws -> MessageModel? {
        try await store.fetchOne(MessageModel.self, id: id)
    }

    /// Rebuild denormalized conversation preview after delete-for-me / delete-for-everyone.
    private func refreshConversationLastMessagePreview(conversationId: String) async throws {
        guard var conversation = try await store.fetchOne(ConversationModel.self, id: conversationId) else {
            return
        }

        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversationId)),
            sort: [SortSpec("timestamp", ascending: false)]
        )
        let candidates = try await store.fetch(MessageModel.self, query: query)
        let last = MessageTimelineVisibility.newestVisible(in: candidates)
        if let last {
            let domain = MessageModelMapper.toDomain(last, fieldCrypto: fieldEncryptionService)
            conversation.lastMessageText = last.isDeleted
                ? nil
                : fieldEncryptionService.encryptOptional(MessageModelMapper.buildLastMessagePreview(domain))
            conversation.lastMessageType = last.type
            conversation.lastMessageSenderName = last.senderName.isEmpty ? nil : last.senderName
            conversation.lastMessageAt = last.timestamp
        } else {
            // Keep discussion; clear preview so UI shows empty placeholder.
            conversation.lastMessageText = nil
            conversation.lastMessageType = nil
            conversation.lastMessageSenderName = nil
            conversation.lastMessageAt = conversation.createdAt
        }
        conversation.updatedAt = Date()
        try await store.save(conversation)
    }

    private func attachReactions(to items: [MessageDataItem]) async throws -> [MessageDataItem] {
        try await Self.attachReactions(to: items, store: store)
    }

    private static func attachReactions(
        to items: [MessageDataItem],
        store: any DatabaseRepositoryProtocol
    ) async throws -> [MessageDataItem] {
        guard !items.isEmpty else { return items }

        var reactionsByMessage: [String: [ReactionItem]] = [:]
        for item in items where !item.codeMessage.isEmpty {
            let query = QuerySpec(
                filter: FilterSpec("message_id == %@", .string(item.codeMessage)),
                sort: [SortSpec("created_at", ascending: true)]
            )
            let models = try await store.fetch(MessageReactionModel.self, query: query)
            if !models.isEmpty {
                reactionsByMessage[item.codeMessage] = models.map {
                    ReactionItem(userId: $0.userId, reaction: $0.emoji)
                }
            }
        }

        return items.map { item in
            guard let reactions = reactionsByMessage[item.codeMessage], !reactions.isEmpty else {
                return item
            }
            var updated = item
            updated.reactions = reactions
            return updated
        }
    }

    private func fetchReactions(messageId: String) async throws -> [ReactionItem] {
        let query = QuerySpec(
            filter: FilterSpec("message_id == %@", .string(messageId)),
            sort: [SortSpec("created_at", ascending: true)]
        )
        let models = try await store.fetch(MessageReactionModel.self, query: query)
        return models.map { ReactionItem(userId: $0.userId, reaction: $0.emoji) }
    }
}
