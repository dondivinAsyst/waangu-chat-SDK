//
//  ChatOutboxSnapshot.swift
//  FeatureChat
//
//  Read-only picture of everything the app still owes the server: the persisted
//  chat outbox (actions waiting for an HTTP flush) and the realtime transport's
//  offline queue (MQTT publishes buffered while the socket was down).
//
//  Diagnostics only — nothing here sends, retries, or clears anything.
//

import Foundation
import WaanguCoreKit

// MARK: - ChatOutboxEntry

/// One persisted outbox action, as stored before any flush attempt.
public struct ChatOutboxEntry: Identifiable, Sendable {
    public let id: String
    public let actionType: String
    public let conversationId: String
    public let idempotencyKey: String
    public let createdAt: Date
    public let syncStatus: OutboxSyncStatus
    public let retryCount: Int
    public let lastError: String?
    public let payloadBytes: Int

    public init(
        id: String,
        actionType: String,
        conversationId: String,
        idempotencyKey: String,
        createdAt: Date,
        syncStatus: OutboxSyncStatus,
        retryCount: Int,
        lastError: String?,
        payloadBytes: Int
    ) {
        self.id = id
        self.actionType = actionType
        self.conversationId = conversationId
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.syncStatus = syncStatus
        self.retryCount = retryCount
        self.lastError = lastError
        self.payloadBytes = payloadBytes
    }

    /// An entry is cleared once the server has acknowledged it. Everything else
    /// — pending, mid-flight, or permanently failed — is still owed.
    public var isCleared: Bool { syncStatus == .synced }
}

// MARK: - ChatQueuedRealtimeMessage

/// One MQTT publish buffered by the realtime transport while it was offline.
public struct ChatQueuedRealtimeMessage: Identifiable, Sendable {
    public let id: String
    public let topicPath: String
    public let qos: RealtimeQoS
    public let priority: MessagePriority
    public let queuedAt: Date
    public let payloadBytes: Int
    public let expiresAt: Date?

    public init(
        id: String,
        topicPath: String,
        qos: RealtimeQoS,
        priority: MessagePriority,
        queuedAt: Date,
        payloadBytes: Int,
        expiresAt: Date?
    ) {
        self.id = id
        self.topicPath = topicPath
        self.qos = qos
        self.priority = priority
        self.queuedAt = queuedAt
        self.payloadBytes = payloadBytes
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}

// MARK: - ChatOutboxSnapshot

/// Both outbound queues as read at a single moment.
public struct ChatOutboxSnapshot: Sendable {

    /// Every stored outbox row, oldest first — the order a flush would send them.
    public let entries: [ChatOutboxEntry]

    /// Publishes the realtime transport is holding, oldest first.
    public let queuedRealtimeMessages: [ChatQueuedRealtimeMessage]

    public let capturedAt: Date

    public init(
        entries: [ChatOutboxEntry],
        queuedRealtimeMessages: [ChatQueuedRealtimeMessage],
        capturedAt: Date = Date()
    ) {
        self.entries = entries
        self.queuedRealtimeMessages = queuedRealtimeMessages
        self.capturedAt = capturedAt
    }

    public static let empty = ChatOutboxSnapshot(
        entries: [],
        queuedRealtimeMessages: []
    )

    /// Rows the server has not acknowledged — what "not yet cleared" means.
    public var uncleared: [ChatOutboxEntry] {
        entries.filter { !$0.isCleared }
    }

    public func count(of status: OutboxSyncStatus) -> Int {
        entries.filter { $0.syncStatus == status }.count
    }

    /// When the oldest unacknowledged row was queued — how far back the
    /// backlog reaches.
    public var oldestUnclearedAt: Date? {
        uncleared.map(\.createdAt).min()
    }

    public var isEmpty: Bool {
        entries.isEmpty && queuedRealtimeMessages.isEmpty
    }
}
