import Foundation
import WaanguCoreKit

actor PresenceRepository: PresenceRepositoryProtocol {

    private let realtime: any RealtimeClientProtocol
    private let database: (any DatabaseRepositoryProtocol)?
    private let presenceStore: UserPresenceStore
    private let currentUserId: () -> String
    private let currentUserPhone: () -> String
    private let currentCountry: () -> String
    private let currentTenantId: () -> String

    /// The live typing and presence subscriptions, cancelled before each
    /// re-attach so a reconnect does not leave the previous one behind.
    private var typingSubscriptionToken: (any RealtimeSubscriptionToken)?
    private var presenceSubscriptionToken: (any RealtimeSubscriptionToken)?

    /// Server conversation id → local row id, and display name per user id.
    /// Typing ticks arrive every few seconds per typist; resolving either from
    /// the database on each one would put the room's keystrokes behind a query.
    private var localConversationIdCache: [String: String] = [:]
    private var displayNameCache: [String: String] = [:]

    init(
        realtime: any RealtimeClientProtocol,
        database: (any DatabaseRepositoryProtocol)? = nil,
        presenceStore: UserPresenceStore = .shared,
        currentUserId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.currentUid },
        currentUserPhone: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.userPhoneNumber },
        currentCountry: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.country },
        currentTenantId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.tenantId }
    ) {
        self.realtime = realtime
        self.database = database
        self.presenceStore = presenceStore
        self.currentUserId = currentUserId
        self.currentUserPhone = currentUserPhone
        self.currentCountry = currentCountry
        self.currentTenantId = currentTenantId
    }

    /// Subscribes to the typing topic and pumps it into `TypingStore` until the
    /// subscription ends, then returns so the caller can re-attach.
    ///
    /// Throws `RealtimeError.notConnected` when the client is not up yet, which
    /// is the normal state at bootstrap — the broker connects after auth, well
    /// after the chat feature loads. A one-shot "start observing" call swallowed
    /// that and left the app subscribed to nothing for the whole session, which
    /// is what the broker's "Message on unsubscribed topic" line was reporting.
    /// `ChatPresenceLifecycle` drives this with the same retry-and-re-attach
    /// supervisor loop the message inbox uses.
    func runTypingFeed() async throws {
        await typingSubscriptionToken?.cancel()
        typingSubscriptionToken = nil

        let stream = try await subscribeTypingStream()
        debugLog("subscribed to \(ChatMQTTTopics.Out.typing.path)", category: "typing")

        for await dto in stream {
            debugLog(
                "tick \(dto.event) from \(dto.userId) in \(dto.conversationId)",
                category: "typing"
            )
            await applyInboundTyping(dto)
        }

        debugLog("feed ended — re-attaching", category: "typing")
    }

    func sendTyping(conversationId: String, type: TypingPayloadType) async {
        let wireConversationId = await outboundConversationId(for: conversationId)
        try? await realtime.publish(
            OutboundTypingDTO(
                senderId: currentUserId(),
                senderPhone: currentUserPhone(),
                conversationId: wireConversationId,
                type: type
            ),
            to: ChatMQTTTopics.In.typing,
            qos: .fireAndForget,
            priority: .low
        )
    }

    func sendUserPresence(status: PresenceStatus, currentRideId: String? = nil) async {
        let userId = currentUserId()
        guard !userId.isEmpty else { return }
        debugLog("publishing presence for user \(userId)", category: "presence")
        let payload = Self.makeOutboundPayload(
            userId: userId,
            status: status,
            country: currentCountry(),
            tenantId: currentTenantId(),
            currentRideId: currentRideId
        )

        try? await realtime.publish(
            payload,
            to: ChatMQTTTopics.In.presence,
            qos: .fireAndForget,
            priority: .low
        )
    }

    /// The presence twin of `runTypingFeed`, driven by the same supervisor.
    ///
    /// Presence had the identical bootstrap problem, and worse: the "started"
    /// flag was set before the subscribe that threw, so nothing ever retried
    /// and inbound presence was dead for the whole session — the broker's
    /// "Message on unsubscribed topic: waangu-chat/presence" line.
    func runPresenceFeed() async throws {
        await presenceSubscriptionToken?.cancel()
        presenceSubscriptionToken = nil

        let stream = try await subscribeUserPresenceStream()
        debugLog("subscribed to \(ChatMQTTTopics.Out.presence.path)", category: "presence")

        for await payload in stream {
            await applyInboundPresence(payload)
        }

        debugLog("feed ended — re-attaching", category: "presence")
    }

    /// Called when a chat room closes.
    ///
    /// Deliberately empty of teardown: typing and presence are session feeds
    /// now, and a closing room must not take them down — the list on the screen
    /// behind it is reading the same feed. Standing typing entries are left
    /// alone too; the peer is still typing, and the list row should say so.
    func cleanup() async {}

    // MARK: - Conversation id wiring

    /// Prefer linked `serverId` on the wire; keep local id until ACK links it.
    private func outboundConversationId(for conversationId: String) async -> String {
        guard let database, !conversationId.isEmpty else { return conversationId }
        if let conversation = try? await database.fetchOne(ConversationModel.self, id: conversationId) {
            return conversation.resolvedServerId
        }
        let byServer = QuerySpec(
            filter: FilterSpec("server_id == %@", .string(conversationId)),
            limit: 1
        )
        if let conversation = try? await database.fetch(ConversationModel.self, query: byServer).first {
            return conversation.resolvedServerId
        }
        return conversationId
    }

    /// Maps whatever id came off the wire to the local conversation row id.
    ///
    /// Peers publish the server id; the room and the list both key off the
    /// local one. Unresolved ids are cached as themselves so a conversation we
    /// have never stored does not re-query on every tick.
    private func localConversationId(for conversationId: String) async -> String {
        guard !conversationId.isEmpty else { return conversationId }
        if let cached = localConversationIdCache[conversationId] { return cached }

        guard let database else { return conversationId }

        // Already a local row id.
        if (try? await database.fetchOne(ConversationModel.self, id: conversationId)) != nil {
            localConversationIdCache[conversationId] = conversationId
            return conversationId
        }

        let byServer = QuerySpec(
            filter: FilterSpec("server_id == %@", .string(conversationId)),
            limit: 1
        )
        guard let conversation = try? await database.fetch(ConversationModel.self, query: byServer).first else {
            // Not stored yet — a conversation created on the peer's side that
            // has not synced here. Left uncached on purpose: caching the miss
            // would outlive the sync and key this conversation wrong for the
            // rest of the session.
            return conversationId
        }

        localConversationIdCache[conversationId] = conversation.id
        return conversation.id
    }

    /// The name to put in "… is typing".
    ///
    /// The server fills `userName` with the sender's phone number when it cannot
    /// resolve one, so the local contact book wins when it knows the sender.
    private func displayName(for userId: String, fallback: String) async -> String {
        guard !userId.isEmpty else { return fallback }
        if let cached = displayNameCache[userId] { return cached }
        guard let database else { return fallback }

        let byUserId = QuerySpec(
            filter: FilterSpec("user_id == %@", .string(userId)),
            limit: 1
        )
        var contact = try? await database.fetch(ContactModel.self, query: byUserId).first

        // The payload carries `senderPhone` and no name at all, and a contact
        // imported from the address book may predate knowing its backend id.
        if contact == nil, !fallback.isEmpty {
            let byPhone = QuerySpec(
                filter: FilterSpec("phone == %@", .string(fallback)),
                limit: 1
            )
            contact = try? await database.fetch(ContactModel.self, query: byPhone).first
        }

        guard let name = contact?.name, !name.isEmpty else { return fallback }

        displayNameCache[userId] = name
        return name
    }

    // MARK: - Outbound

    private static func makeOutboundPayload(
        userId: String,
        status: PresenceStatus,
        country: String,
        tenantId: String,
        currentRideId: String?
    ) -> PresencePayloadDTO {
        let lastSeen: String?
        if status == .offline {
            lastSeen = ISO8601DateFormatter().string(from: Date())
        } else {
            lastSeen = nil
        }

        return PresencePayloadDTO(
            userId: userId,
            status: status,
            lastSeen: lastSeen,
            country: country.isEmpty ? nil : country,
            tenantId: tenantId.isEmpty ? nil : tenantId,
            currentRideId: currentRideId
        )
    }

    // MARK: - Inbound

    private func subscribeUserPresenceStream() async throws -> AsyncStream<PresencePayloadDTO> {
        let (stream, token) = try await realtime.subscribe(
            to: ChatMQTTTopics.Out.presence,
            as: ChatMqttJSONBox.self,
            // NOT `.activityIndicator`. That is `.debounce(1s)`, and the
            // registry's debounce branch returns nil and relies on a flush that
            // never yields the payload — every message on such a subscription is
            // dropped for good. A handful of latest ticks is what this wants
            // anyway; the sender already throttles to one every 3s.
            buffering: .bufferNewest(8),
            qos: .fireAndForget
        )
        presenceSubscriptionToken = token

        let myUserId = currentUserId()

        return AsyncStream { continuation in
            let task = Task {
                for await box in stream {
                    guard let payload = Self.parsePresencePayload(box.data) else { continue }
                    guard payload.userId != myUserId else { continue }
                    continuation.yield(payload)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func applyInboundPresence(_ payload: PresencePayloadDTO) async {
        presenceStore.set(payload)

        guard payload.status == .offline,
              let database,
              let lastSeen = Self.parseLastSeenDate(payload.lastSeen) else {
            return
        }

        do {
            let query = QuerySpec(
                filter: FilterSpec("user_id == %@", .string(payload.userId)),
                limit: 1
            )
            guard var contact = try await database.fetch(ContactModel.self, query: query).first else {
                return
            }
            contact.lastSeenAt = lastSeen
            contact.updatedAt = Date()
            try await database.save(contact)
        } catch {
            // Presence is best-effort; ignore persistence failures.
        }
    }

    private static func parsePresencePayload(_ data: Data) -> PresencePayloadDTO? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let payload = (json["payload"] as? [String: Any]) ?? json
        guard let userId = payload["userId"] as? String,
              let statusRaw = (payload["status"] as? String)?.uppercased(),
              let status = PresenceStatus(rawValue: statusRaw) else {
            return nil
        }

        let lastSeen = payload["lastSeen"] as? String
        let country = payload["country"] as? String
        let tenantId = payload["tenantId"] as? String
        let currentRideId = payload["currentRideId"] as? String

        return PresencePayloadDTO(
            userId: userId,
            status: status,
            lastSeen: lastSeen,
            country: country,
            tenantId: tenantId,
            currentRideId: currentRideId
        )
    }

    private static func parseLastSeenDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return Date() }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? Date()
    }

    // MARK: - Typing

    private func subscribeTypingStream() async throws -> AsyncStream<InboundPresenceDTO> {
        let (stream, token) = try await realtime.subscribe(
            to: ChatMQTTTopics.Out.typing,
            as: ChatMqttJSONBox.self,
            // NOT `.activityIndicator`. That is `.debounce(1s)`, and the
            // registry's debounce branch returns nil and relies on a flush that
            // never yields the payload — every message on such a subscription is
            // dropped for good. A handful of latest ticks is what this wants
            // anyway; the sender already throttles to one every 3s.
            buffering: .bufferNewest(8),
            qos: .fireAndForget
        )
        typingSubscriptionToken = token

        return AsyncStream { continuation in
            let task = Task {
                for await box in stream {
                    guard let dto = Self.parseTypingPayload(box.data, myUserId: currentUserId()) else {
                        continue
                    }
                    continuation.yield(dto)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Feeds one inbound tick into the store, keyed by the local conversation id.
    private func applyInboundTyping(_ dto: InboundPresenceDTO) async {
        let conversationId = await localConversationId(for: dto.conversationId)
        if conversationId != dto.conversationId {
            debugLog("wire id \(dto.conversationId) → local \(conversationId)", category: "typing")
        }

        switch dto.event {
        case "typing", "recordingVoice", "recordingVideo":
            let name = await displayName(for: dto.userId, fallback: dto.userName)
            let user = TypingUser(
                name: name,
                msg: dto.event,
                senderId: dto.userId,
                conversationId: conversationId,
                groupeId: conversationId,
                messageType: dto.event == "typing" ? .TEXT : .AUDIO
            )
            await TypingStore.shared.set(user)

        case "idle", "offline":
            // Not every peer sends one — entries expire on their own — but when
            // it arrives it should drop the indicator without waiting for the TTL.
            await TypingStore.shared.clear(senderId: dto.userId, conversationId: conversationId)

        default:
            break
        }
    }

    private static func parseTypingPayload(_ data: Data, myUserId: String) -> InboundPresenceDTO? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let eventType = (json["eventType"] as? String)?.uppercased()
        guard eventType == nil || eventType == ChatMqttEvents.typing else { return nil }

        let payload = (json["payload"] as? [String: Any]) ?? json
        guard let conversationId = payload["conversationId"] as? String,
              let userId = (payload["userId"] as? String) ?? (payload["senderId"] as? String) else {
            debugLog("dropped: payload has no conversationId/senderId", category: "typing")
            return nil
        }

        guard userId != myUserId else {
            debugLog("dropped: own echo", category: "typing")
            return nil
        }

        let userName = (payload["userName"] as? String)
            ?? (payload["senderName"] as? String)
            ?? (payload["senderPhone"] as? String)
            ?? ""
        let event = resolveTypingEvent(from: payload)
        let timestamp = (payload["timestamp"] as? Double) ?? Date().timeIntervalSince1970

        return InboundPresenceDTO(
            conversationId: conversationId,
            userId: userId,
            userName: userName,
            event: event,
            timestamp: timestamp
        )
    }

    private static func resolveTypingEvent(from payload: [String: Any]) -> String {
        if let type = (payload["type"] as? String)?.uppercased() {
            switch type {
            case TypingPayloadType.text.rawValue:
                return "typing"
            case TypingPayloadType.audio.rawValue:
                return "recordingVoice"
            default:
                break
            }
        }

        return (payload["event"] as? String)
            ?? (payload["typingStatus"] as? String)
            ?? "typing"
    }
}
