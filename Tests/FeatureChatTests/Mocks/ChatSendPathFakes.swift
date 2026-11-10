//
//  ChatSendPathFakes.swift
//  FeatureChatTests
//
//  Doublures du chemin d'envoi d'un message ordinaire : dépôt de conversations,
//  outbox et temps réel. Elles consignent ce que `SendMessageUseCase` leur
//  confie, et rien d'autre — aucune n'a de dépendance financière.
//

import Foundation
import WaanguCoreKit
@testable import WaanguFeatureChat

enum ChatSendPathFakeError: Error {
    /// Méthode que le chemin d'envoi n'est pas censé appeler.
    case unexpectedCall
}

/// Dépôt de conversations en mémoire. Consigne les conversations sauvegardées.
final class RecordingDiscussionRepository: DiscussionRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _saved: [DiscussionChatItem] = []

    var saved: [DiscussionChatItem] { lock.withLock { _saved } }

    func fetchDiscussions() async throws -> [DiscussionChatItem] { [] }
    func getDiscussionById(conversationId: String) async throws -> DiscussionChatItem? { nil }
    func fetchMessages(_ conversationId: String) async throws -> [MessageDataItem] { [] }
    func fetchMessagesWithPagination(conversationId: String,
                                     before cursor: Date?,
                                     pageSize: Int) async throws -> [MessageDataItem] { [] }
    func saveDiscussion(_ discussion: DiscussionChatItem) async throws {
        lock.withLock { _saved.append(discussion) }
    }
    func updateDiscussionSetting(_ discussion: DiscussionChatItem) async throws {}
    func deleteDiscussion(conversationId: String) async throws {}
    func deleteAllDiscussionMessages(conversationId: String) async throws {}
    func clearUnreadCount(conversationId: String) async throws {}
    func saveDraft(conversationId: String, text: String) async throws {}
    func fetchDraft(conversationId: String) async throws -> String? { nil }
    func outboundConversationId(for localConversationId: String) async -> String { localConversationId }
    func outboundGroupId(for localConversationId: String) async -> String? { nil }
    func syncConversations(since: Date?, limit: Int) async throws -> ConversationSyncResult {
        throw ChatSendPathFakeError.unexpectedCall
    }
    func syncConversationMessages(conversationId: String, since: Date?, limit: Int) async throws -> Int { 0 }
    func performFullSync(limit: Int) async throws {}
    func deduplicateConversationsIfNeeded() async {}
}

/// Outbox du chat en mémoire. Consigne les éléments enfilés.
final class RecordingChatOutbox: ChatOutboxEnqueuing, @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [ChatOutboxItem] = []

    var items: [ChatOutboxItem] { lock.withLock { _items } }

    func enqueue(_ item: ChatOutboxItem) async throws {
        lock.withLock { _items.append(item) }
    }
}

/// Client temps réel connecté qui consigne les chemins publiés.
final class RecordingRealtimeClient: RealtimeClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _publishedPaths: [String] = []
    private var _publishedBodies: [Data] = []
    private var _connectCount = 0
    private var _disconnects: [DisconnectReason] = []

    var publishedPaths: [String] { lock.withLock { _publishedPaths } }
    /// Each published payload, JSON-encoded as it would go on the wire.
    var publishedBodies: [Data] { lock.withLock { _publishedBodies } }
    var connectCount: Int { lock.withLock { _connectCount } }
    var disconnects: [DisconnectReason] { lock.withLock { _disconnects } }

    /// Called with "connect" / "disconnect" so a test can order them against other fakes.
    var onEvent: (@Sendable (String) -> Void)?
    /// When set, `connect()` throws it.
    var connectError: Error?

    var connectionState: RealtimeConnectionState { get async { .connected } }
    func observeConnectionState() -> AsyncStream<RealtimeConnectionState> { AsyncStream { $0.finish() } }
    func connect() async throws {
        lock.withLock { _connectCount += 1 }
        onEvent?("connect")
        if let connectError { throw connectError }
    }
    func disconnect(reason: DisconnectReason, flushQueue: Bool) async throws {
        lock.withLock { _disconnects.append(reason) }
        onEvent?("disconnect")
    }

    func subscribe<T: Decodable & Sendable>(
        to topic: RealtimeTopic,
        as type: T.Type,
        buffering: RealtimeBufferingPolicy,
        qos: RealtimeQoS
    ) async throws -> (stream: AsyncStream<T>, token: any RealtimeSubscriptionToken) {
        throw ChatSendPathFakeError.unexpectedCall
    }

    func publish<T: Encodable & Sendable>(
        _ payload: T,
        to topic: RealtimeTopic,
        qos: RealtimeQoS,
        priority: MessagePriority
    ) async throws {
        let body = (try? JSONEncoder().encode(payload)) ?? Data()
        lock.withLock {
            _publishedPaths.append(topic.path)
            _publishedBodies.append(body)
        }
    }

    func request<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ payload: Request,
        to topic: RealtimeTopic,
        replyOn: RealtimeTopic,
        as responseType: Response.Type,
        timeout: TimeInterval
    ) async throws -> Response {
        throw ChatSendPathFakeError.unexpectedCall
    }

    func publishPresence(_ state: PresenceState, to topic: RealtimeTopic) async throws {}
    func observePresence(on topic: RealtimeTopic) -> AsyncStream<PresenceInfo> { AsyncStream { $0.finish() } }
    func cancelSubscription(_ token: any RealtimeSubscriptionToken) async {}
    func cancelAllSubscriptions(forFeature feature: String) async {}
    var activeSubscriptionCount: Int { get async { 0 } }
    func isSubscribed(to topic: RealtimeTopic) async -> Bool { false }
    func subscriptionDiagnostics() async -> [RealtimeSubscriptionDiagnostic] { [] }
    func register(_ registrations: [TopicRegistration]) async {}

    let offlineQueue: any OfflineQueueProtocol = EmptyOfflineQueue()
}

/// File hors ligne toujours vide.
struct EmptyOfflineQueue: OfflineQueueProtocol {
    func enqueue(_ item: OfflineQueueItem) async throws {}
    func flush(handler: @Sendable (OfflineQueueItem) async throws -> Bool) async -> OfflineFlushResult {
        OfflineFlushResult(sentCount: 0, expiredCount: 0, failedCount: 0, duration: 0)
    }
    var pendingCount: Int { get async { 0 } }
    func pendingItems() async -> [OfflineQueueItem] { [] }
    func clear() async {}
    func purgeExpired() async -> Int { 0 }
    func clear(for topic: RealtimeTopic) async {}
}
