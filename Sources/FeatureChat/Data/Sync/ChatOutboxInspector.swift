//
//  ChatOutboxInspector.swift
//  FeatureChat
//
//  Reads the two outbound queues for the diagnostics screen:
//    - the persisted chat outbox (`ChatOutboxItem` rows awaiting an HTTP flush)
//    - the realtime transport's offline queue (MQTT publishes buffered offline)
//
//  Strictly read-only. It never enqueues, flushes, retries, or deletes.
//

import Foundation
import WaanguCoreKit

public struct ChatOutboxInspector: ChatOutboxInspecting {

    private let database: any DatabaseRepositoryProtocol
    private let realtime: any RealtimeClientProtocol

    public init(
        database: any DatabaseRepositoryProtocol,
        realtime: any RealtimeClientProtocol
    ) {
        self.database = database
        self.realtime = realtime
    }

    public func snapshot() async throws -> ChatOutboxSnapshot {
        // Fetched unfiltered and ordered here rather than through a QuerySpec:
        // the outbox is small by design, and sorting in Swift gives the same
        // oldest-first order a flush walks whatever storage backs the rows.
        let items = try await database.fetch(ChatOutboxItem.self, query: nil)

        let entries = items
            .sorted { $0.createdAt < $1.createdAt }
            .map(Self.entry(from:))

        let queued = await realtime.offlineQueue.pendingItems()
            .sorted { $0.timestamp < $1.timestamp }
            .map(Self.queuedMessage(from:))

        return ChatOutboxSnapshot(
            entries: entries,
            queuedRealtimeMessages: queued
        )
    }

    // MARK: - Mapping

    private static func entry(from item: ChatOutboxItem) -> ChatOutboxEntry {
        ChatOutboxEntry(
            id: item.id,
            actionType: item.actionTypeString,
            conversationId: item.conversationId,
            idempotencyKey: item.idempotencyKey,
            createdAt: item.createdAt,
            syncStatus: item.syncStatus,
            retryCount: item.retryCount,
            lastError: item.lastError,
            payloadBytes: item.payload.count
        )
    }

    private static func queuedMessage(
        from item: OfflineQueueItem
    ) -> ChatQueuedRealtimeMessage {
        ChatQueuedRealtimeMessage(
            id: item.id.lowercasedString,
            topicPath: item.topic.path,
            qos: item.qos,
            priority: item.priority,
            queuedAt: item.timestamp,
            payloadBytes: item.payloadData.count,
            expiresAt: item.ttl.map { item.timestamp.addingTimeInterval($0) }
        )
    }
}
