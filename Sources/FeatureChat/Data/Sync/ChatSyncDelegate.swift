import Foundation
import WaanguCoreKit
import os

/// Unified-logging channel for the chat inbound path.
///
/// `os.Logger` rather than `AppLogger` for the same reason the realtime client
/// gives: this runs once per inbound frame, and `AppLogger` is an actor — an
/// `await` per message would put back-pressure on the receive loop.
private let chatInboundLog = Logger(subsystem: "com.waangu.featurechat", category: "inbound")

public struct ChatSyncDelegate: SyncDelegate {
    public typealias SyncEvent = ChatSyncEventDTO

    /// Not private: the group-roster half of this delegate lives in its own file
    /// and needs the same encryption for participant display names.
    let fieldCrypto: any FieldEncryptionServiceProtocol
    /// Not private: the conversation and call sync halves live in their own files
    /// and both have to tell our own rows apart from everyone else's.
    let currentUserId: () -> String
    private let realtime: (any RealtimeClientProtocol)?
    private let outbox: (any ChatOutboxEnqueuing)?
    private let outboxMaintenance: (any ChatOutboxMaintaining)?

    /// Signale qu'un objet financier a changé.
    ///
    /// Fermeture et non dépendance directe sur les cas d'usage financiers : le
    /// délégué de synchronisation n'a pas à connaître la finance, il transporte
    /// un signal. Cela lui évite aussi de porter le magasin d'objets, dont le
    /// cycle de vie est celui de la session et non celui de la sync.
    ///
    /// Le handler reçoit une **référence**, jamais un état : c'est ce qui garantit
    /// qu'un statut ne peut pas remonter par le fil temps réel.
    private let onFinancialObjectChanged: (@Sendable (FinancialReference) async -> Void)?

    /// Un message `ISMONEY` vient d'arriver — Bloc 1 §11.2, « push avant le
    /// message : la carte s'affiche après requête serveur ».
    ///
    /// Le pointeur MQTT peut précéder le message (il part dès le prepare) : la
    /// lecture qu'il déclenche ne trouve alors aucune bulle à réécrire, et la
    /// bulle arrivée ensuite gardait l'état publié par l'expéditeur. Même
    /// contrat que ci-dessus : une référence, jamais un état.
    private let onFinancialMessageReceived: (@Sendable (FinancialReference) async -> Void)?

    /// Mesures sans contenu remises à l'hôte (plan SDK, étape 1.13).
    private let metricsSink: any ChatMetricsSink

    public var featureName: String { "chat" }

    public init(
        fieldCrypto: any FieldEncryptionServiceProtocol,
        currentUserId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.currentUid },
        realtime: (any RealtimeClientProtocol)? = nil,
        outbox: (any ChatOutboxEnqueuing)? = nil,
        outboxMaintenance: (any ChatOutboxMaintaining)? = nil,
        onFinancialObjectChanged: (@Sendable (FinancialReference) async -> Void)? = nil,
        onFinancialMessageReceived: (@Sendable (FinancialReference) async -> Void)? = nil,
        metricsSink: any ChatMetricsSink = NoChatMetrics()
    ) {
        self.fieldCrypto = fieldCrypto
        self.currentUserId = currentUserId
        self.realtime = realtime
        self.outbox = outbox
        self.outboxMaintenance = outboxMaintenance
        self.onFinancialObjectChanged = onFinancialObjectChanged
        self.onFinancialMessageReceived = onFinancialMessageReceived
        self.metricsSink = metricsSink
    }

    public func pullInboxSummary(
        apiClient: any APIClientProtocol,
        database: any DatabaseRepositoryProtocol
    ) async -> Bool {
        // Le compte qui a émis la requête : la purge de déconnexion est ponctuelle,
        // une réponse tardive repeuplerait la base d'un compte déjà parti (F-04).
        let requester = currentUserId()
        do {
            let response: ChatInboxSummaryResponseDTO = try await apiClient.request(
                endpoint: HTTPChatSyncEndpoints.inboxSummary
            )
            for summary in response.conversations {
                guard currentUserId() == requester else { return false }
                if let lastMessage = summary.lastMessage,
                   ConversationSystemRecord.kind(of: lastMessage) == nil,
                   let incoming = MessageModelMapper.toModel(from: lastMessage, fieldCrypto: fieldCrypto) {
                    // Même fusion que le flux temps réel : le résumé ne doit pas
                    // défaire une suppression ni rendre une citation vidée (B44).
                    let (_, model) = await mergedForSave(incoming, database: database)
                    try? await database.save(model)
                }
            }
            return !response.conversations.isEmpty
        } catch {
            return false
        }
    }

    public func fetchPage(
        since: Date?,
        cursor: String?,
        limit: Int,
        apiClient: any APIClientProtocol
    ) async throws -> SyncPage<ChatSyncEventDTO> {
        let sinceDate = since ?? Date(timeIntervalSince1970: 0)
        let response: ChatPullEventsResponseDTO = try await apiClient.request(
            endpoint: HTTPChatSyncEndpoints.pullEvents(
                since: sinceDate,
                cursor: cursor,
                limit: limit
            )
        )
        return SyncPage(
            events: response.events,
            nextCursor: response.nextCursor,
            hasMore: response.hasMore
        )
    }

    /// N-02 : applique l'événement et dit si une écriture a été refusée.
    public func applyEvent(
        _ event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async -> SyncApplyOutcome {
        let recorder = WriteRecordingDatabase(wrapping: database)
        await processEvent(event, database: recorder)
        if let reason = await recorder.firstWriteError { return .failed(reason: reason) }
        return .applied
    }

    public func processEvent(
        _ event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        switch event.type {
        case "message":
            guard let dto = event.decodePayload(as: InboundMessageDTO.self),
                  var incoming = MessageModelMapper.toModel(from: dto, fieldCrypto: fieldCrypto) else {
                return
            }
          
            guard let conversationId = await ensureConversation(
                for: dto,
                incoming: incoming,
                database: database
            ) else {
                return
            }

            // After the conversation exists — a "created" record may be how it
            // first reaches this device — but never stored as a message.
            if let kind = ConversationSystemRecord.kind(of: dto) {
                await saveSystemRecordCheckpoint(dto, kind: kind, conversationId: conversationId, database: database)
                return
            }
            debugLog("inbound message → conversation \(conversationId)", category: "chat-sync")
            incoming.conversationId = conversationId

            if dto.senderId != currentUserId() {
                await upsertDirectPeerParticipant(
                    peerUserId: dto.senderId,
                    displayNameHint: dto.senderName,
                    phoneHint: dto.senderPhone,
                    avatarHint: dto.senderAvatar,
                    conversationId: conversationId,
                    database: database
                )

                // Sending is how a burst usually ends, and nothing says so on
                // the typing topic. Left to expire, "typing…" would sit next to
                // the message that just arrived for a few more seconds.
                await TypingStore.shared.clear(
                    senderId: dto.senderId,
                    conversationId: conversationId
                )
            }

            let (existing, model) = await mergedForSave(incoming, database: database)

            let groupEvent = dto.resolvedGroupEvent

            do {
                try await database.save(model)

                // Before telling the list to reload: the roster writes the title,
                // the members and the sync metadata the list filters on, so
                // refreshing first would reload a list the group is still missing
                // from, and nothing would refresh it again.
                if let groupEvent {
                    await applyGroupRoster(
                        groupEvent,
                        conversationId: conversationId,
                        database: database
                    )
                }

                notifyDiscussionsShouldRefresh()

                // Après l'écriture : la lecture serveur réécrit la ligne, qui
                // doit donc exister. Une seule fois par message — une nouvelle
                // livraison du même ne relance rien.
                if existing == nil,
                   let reference = Self.financialReference(of: model),
                   let handler = onFinancialMessageReceived {
                    await handler(reference)
                }

                // A group event was projected into the thread, not sent to us, and
                // the id it carries may be one this device derived — the server
                // cannot resolve it, so there is nothing to acknowledge.
                if existing == nil,
                   groupEvent == nil,
                   dto.senderId != currentUserId(),
                   let conversationId = dto.conversationId {
                    await publishMarkDelivered(
                        codeMessage: dto.codeMessage,
                        conversationId: conversationId,
                        database: database
                    )
                }
            } catch {
                debugLog("this was a message event in chat sync delegate processEvent error occur : \(error)")
            }

        case "message_edited":
            await applyModifiedMessageEvent(event, database: database)

        case "reaction":
            await applyInboundReactionEvent(event, removing: false, database: database)

        case "reaction_removed":
            await applyInboundReactionEvent(event, removing: true, database: database)

        case "poll_vote":
            await applyInboundPollVoteEvent(event, database: database)

        case "message_deleted":
            let dto = event.decodePayload(as: InboundMessageDeleteDTO.self)
            let messageId = event.referenceId?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? dto?.resolvedMessageId
            guard let messageId, !messageId.isEmpty else { return }

            let forEveryone = dto?.resolvedForEveryone ?? true
            let deleterId = dto?.resolvedDeleterId ?? ""

            // Delete-for-me is device-local to the deleter — only apply when it's us
            // (multi-device sync). Delete-for-everyone applies for all participants.
            if !forEveryone, !deleterId.isEmpty, deleterId != currentUserId() {
                return
            }

            if var existing = try? await database.fetchOne(MessageModel.self, id: messageId) {
                // Les fichiers se retrouvent par le nom porté par le contenu :
                // à relever avant de vider celui-ci.
                let beforeDelete = MessageModelMapper.toDomain(existing, fieldCrypto: fieldCrypto)
                existing.isDeleted = true
                existing.deletedAt = existing.deletedAt ?? Date()
                existing.searchText = nil   // legacy rows: no plaintext survives a delete
                existing.updatedAt = Date()
                if forEveryone {
                    existing.isDeletedForAll = true
                    existing.content = Self.redactedContent(of: existing.content)
                    // Confirmed by server — hide ticks on deleted bubble.
                    if existing.deliveryStatus == .pending {
                        existing.deliveryStatus = .sent
                    }
                }
                try? await database.save(existing)
                if forEveryone {
                    await redactQuotes(ofDeletedMessage: existing.id,
                                       conversationId: existing.conversationId,
                                       database: database)
                }
                // Supprimé ailleurs : les fichiers reçus partent aussi, comme pour
                // une suppression faite depuis cet appareil (B44).
                ChatRoomMessageMediaCleanup.deleteMediaFiles(for: beforeDelete)
                await refreshConversationLastMessageAfterDelete(
                    conversationId: existing.conversationId,
                    database: database
                )
                notifyDiscussionsShouldRefresh()
            }

        case "delete_ack":
            await settleOutbox(.deleteMessage, event: event, acknowledged: true)
            await applyDeleteAck(event: event, success: true, database: database)
            notifyDiscussionsShouldRefresh()

        case "delete_failed":
            await settleOutbox(.deleteMessage, event: event, acknowledged: false)
            await applyDeleteAck(event: event, success: false, database: database)
            notifyDiscussionsShouldRefresh()

        case "sent_receipt":
            await settleOutbox(.sendMessage, event: event, acknowledged: true)
            await applyDeliveryStatus(
                event: event,
                status: .sent,
                database: database
            )
            await linkConversationServerIdIfNeeded(event: event, database: database)
            await insertOwnMessageFromAckIfMissing(event: event, database: database)
            await clearUnreadAndPublishReadReceipts(
                conversationId: event.conversationId,
                database: database
            )
            notifyDiscussionsShouldRefresh()

        case "modify_ack":
            await settleOutbox(.modifyMessage, event: event, acknowledged: true)
            await applyModifyAck(event: event, success: true, database: database)
            notifyDiscussionsShouldRefresh()

        case "modify_failed":
            await settleOutbox(.modifyMessage, event: event, acknowledged: false)
            await applyModifyAck(event: event, success: false, database: database)
            notifyDiscussionsShouldRefresh()

        case "send_failed":
            await settleOutbox(.sendMessage, event: event, acknowledged: false)
            await applyDeliveryStatus(
                event: event,
                status: .failed,
                database: database
            )
            notifyDiscussionsShouldRefresh()

        case "delivery_receipt":
            await applyInboundDeliveryReceipt(event: event, database: database)
            notifyDiscussionsShouldRefresh()

        case "read_receipt":
            await applyDeliveryStatus(
                event: event,
                status: .read,
                database: database
            )
            notifyDiscussionsShouldRefresh()

        case "read_ack":
            await settleOutbox(.readReceipt, event: event, acknowledged: true)
            await clearUnreadLocallyForReadAck(
                conversationId: event.conversationId,
                database: database
            )
            notifyDiscussionsShouldRefresh()

        case "presence":
            break

        case "story_created":
            await applyStoryCreatedEvent(event, database: database)

        case "story_viewed":
            await applyStoryViewedEvent(event, database: database)

        case "story_deleted":
            await applyStoryDeletedEvent(event, database: database)

        case "story_reacted":
            await applyStoryReactedEvent(event, database: database)

        case "story_expired":
            await applyStoryExpiredEvent(event, database: database)

        // Live location is the one branch here that takes no `database`: a tick
        // has a Redis TTL behind it and belongs in the feed only as the
        // `LOCATION` anchor message it moves. Persisting one would put a row in
        // the timeline every few seconds for the length of the share.
        case "live_location_update":
            applyLiveLocationEvent(event, isLive: true)

        case "live_location_stop":
            applyLiveLocationEvent(event, isLive: false)
            // The ticks stay in memory; the end of the share does not. This is
            // the only branch here that writes, and it has to: a watcher who
            // relaunches has nothing left in memory to tell them the share is
            // over, and would read the anchor as live all over again.
            await persistLiveLocationStop(event, database: database)

        // Un objet financier a changé. On ne lit rien du payload au-delà de son
        // identité : la vérité se demande au serveur, elle n'arrive pas par le fil.
        case "finance_object_changed":
            await applyFinancialObjectChanged(event)

        // Un litige s'est ouvert ou fermé : les cartes de litige se relisent.
        case "finance_dispute_changed":
            await MainActor.run {
                NotificationCenter.default.post(name: .financialDisputeChanged, object: nil)
            }

        default:
            break
        }
    }

    /// La référence portée par un message de paiement, pour la lecture serveur.
    ///
    /// **Sans nature sur le fil, aucune lecture.** Elle retombait sur `PAYMENT` :
    /// une demande d'argent reçue sans type était lue comme un paiement, typée
    /// comme tel, et s'affichait « Argent reçu ». La carte d'attente est
    /// honnête ; une nature devinée ne l'est pas. Révision 0 : c'est le serveur
    /// qui la donne, jamais le message.
    static func financialReference(of model: MessageModel) -> FinancialReference? {
        guard model.type == .payment,
              let id = model.content.paymentRef?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              let type = model.content.financialObjectType.flatMap(FinancialObjectType.init(rawValue:)),
              type.isKnown
        else { return nil }
        return FinancialReference(
            type: type,
            id: id,
            version: 0,
            correlationID: model.content.financialCorrelationId.map(CorrelationId.init(value:)) ?? CorrelationId()
        )
    }

    /// Transforme la notification en référence et la remonte au handler.
    ///
    /// N'écrit rien en base et ne touche à aucun état : la lecture serveur et le
    /// garde de version sont la responsabilité du magasin financier. Ce chemin
    /// existe uniquement pour dire « va regarder ».
    private func applyFinancialObjectChanged(_ event: ChatSyncEventDTO) async {
        guard let handler = onFinancialObjectChanged else { return }
        guard let dto = event.decodePayload(as: FinancialEventDTO.self),
              let reference = dto.toReference() else {
            // Type inconnu de cette version, ou payload incomplet. Rien à
            // requêter — mais surtout, rien n'est inventé.
            return
        }
        await handler(reference)
    }

    /// Puts a live location tick in memory, where the map reads it.
    ///
    /// A stop that carried no final position freezes the pin already held —
    /// there is nothing new to store, and the share simply ends.
    private func applyLiveLocationEvent(_ event: ChatSyncEventDTO, isLive: Bool) {
        guard let dto = event.decodePayload(as: InboundLiveLocationDTO.self) else { return }

        guard let tick = LiveLocationMapper.toTick(
            from: dto,
            at: event.date,
            isLive: isLive
        ) else {
            if !isLive {
                LiveLocationStore.shared.markStopped(shareId: dto.shareId)
            }
            return
        }

        LiveLocationStore.shared.apply(tick)
    }

    /// Records the end of a share on the anchor message itself.
    ///
    /// `isLiveLocation` is left true and the deadline moved instead: the bubble
    /// still has to say it *was* a live share so it can say the share ended,
    /// and a deadline in the past is what every reader already treats as over.
    ///
    /// A stop for a message this device never stored is nothing to patch —
    /// same as an inbound reaction for an unknown message.
    private func persistLiveLocationStop(
        _ event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let dto = event.decodePayload(as: InboundLiveLocationDTO.self) else { return }

        let messageId = dto.codeMessage ?? dto.shareId
        guard !messageId.isEmpty,
              var message = try? await database.fetchOne(MessageModel.self, id: messageId),
              let patched = LiveLocationStopPatch.apply(
                  to: message.content,
                  endedAt: event.at,
                  latitude: dto.location?.latitude,
                  longitude: dto.location?.longitude
              )
        else { return }

        message.content = patched
        message.updatedAt = Date()
        try? await database.save(message)
    }

    /// Live inbox: `waangu-chat/{userId}`. Typing/presence stay on PresenceRepository.
    public func realtimeSubscription(
        realtime: any RealtimeClientProtocol
    ) async throws -> RealtimeSync<ChatSyncEventDTO>? {
        let userId = currentUserId()
       
        guard !userId.isEmpty else { return nil }

        let inboxTopic = ChatMQTTTopics.userInbox(userId: userId)
   
        let (topicStream, token) = try await realtime.subscribe(
            to: inboxTopic,
            as: ChatMqttJSONBox.self,
            buffering: .unbounded,
            qos: .atLeastOnce
        )
        let (stream, continuation) = AsyncStream<ChatSyncEventDTO>.makeStream()
        let topic = inboxTopic.path
        Task {
            for await box in topicStream {
                guard let event = ChatMqttEventParser.parse(data: box.data) else {
                    // The parser's `default:` branch returns nil for any
                    // eventType it does not handle, and that drop was total —
                    // no trace anywhere. Name the event that was dropped, or a
                    // backend adding one is indistinguishable from a bug.
                    let dropped = ChatMqttEventParser.peekEventType(data: box.data)

                    if let dropped, ChatMqttEvents.isHandledElsewhere(dropped) {
                        // Typing, or a call event bound for CallSignalingRepository
                        // on this same topic. Expected, and far too frequent to
                        // warn about.
                        chatInboundLog.debug(
                            "\u{1F4EC} CHAT skip=\(dropped, privacy: .public) topic=\(topic, privacy: .public)"
                        )
                    } else {
                        chatInboundLog.warning(
                            """
                            \u{1F4EC} CHAT drop=unhandled topic=\(topic, privacy: .public) \
                            event=\(dropped ?? "<none>", privacy: .public) \
                            bytes=\(box.data.count, privacy: .public)
                            """
                        )
                    }
                    continue
                }

                chatInboundLog.info(
                    """
                    \u{1F4EC} CHAT topic=\(topic, privacy: .public) \
                    event=\(ChatMqttEventParser.peekEventType(data: box.data) ?? "<none>", privacy: .public) \
                    \u{2192} type=\(event.type, privacy: .public) \
                    ref=\(event.referenceId ?? "-", privacy: .public) \
                    conv=\(event.conversationId ?? "-", privacy: .public)
                    """
                )

                continuation.yield(event)
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in
            Task { await token.cancel() }
        }

        return RealtimeSync(stream: stream, token: token)
    }

    public func didFlush(
        results: [OutboxFlushResult],
        database: any DatabaseRepositoryProtocol
    ) async {
        for result in results {
            await applyFlushResult(result, database: database)
        }
    }
}

// Internal rather than file-private: the conversation and call sync halves are
// separate files, and they reach the database through these same helpers. Their
// whole point is that a conversation arriving by sync lands exactly where one
// arriving by MQTT lands.
extension ChatSyncDelegate {

    func notifyDiscussionsShouldRefresh() {
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }

    func notifyStatusesShouldRefresh() {
        NotificationCenter.default.post(name: .statusesShouldRefresh, object: nil)
    }

    func applyStoryCreatedEvent(
        _ event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
       
        guard let dto = event.decodePayload(as: InboundStoryCreatedDTO.self),
              var model = StatusModelMapper.toModel(from: dto, at: event.date) else {
            return
        }
 
        // Payload often omits creatorName / avatar — fill from local contacts.
        if model.userName.isEmpty || model.avatarURL == nil {
            if let contact = await findSyncedContact(
                userId: model.userId,
                phone: "",
                database: database
            ) {
                if model.userName.isEmpty {
                    model.userName = fieldCrypto.decrypt(contact.name)
                }
                if model.avatarURL == nil {
                    model.avatarURL = contact.avatarURL
                }
            }
        }

        // Own story: REST/MQTT may race — upsert for multi-device sync without duplicating.
        // MQTT delivery means the server accepted the story → always mark synced (don't keep a
        // stale .failed from a decode/race on the HTTP response).
        if model.userId == currentUserId() {
            if let existing = try? await database.fetchOne(StatusModel.self, id: model.id) {
                model.syncStatus = .synced
                if model.userName.isEmpty { model.userName = existing.userName }
                if model.avatarURL == nil { model.avatarURL = existing.avatarURL }
                if model.mediaURL == nil { model.mediaURL = existing.mediaURL }
                if model.thumbnailURL == nil { model.thumbnailURL = existing.thumbnailURL }
                if model.localPath == nil { model.localPath = existing.localPath }
                model.viewed = existing.viewed
                model.viewCount = max(model.viewCount, existing.viewCount)
            } else {
                model.syncStatus = .synced
            }
            try? await database.save(model)
            notifyStatusesShouldRefresh()
            return
        }
    
        if let existing = try? await database.fetchOne(StatusModel.self, id: model.id) {
            // Refresh media URLs / caption if the same story is re-delivered.
            var updated = existing
            updated.mediaURL = model.mediaURL ?? existing.mediaURL
            updated.thumbnailURL = model.thumbnailURL ?? existing.thumbnailURL
            updated.caption = model.caption ?? existing.caption
            updated.text = model.text ?? existing.text
            updated.expiresAt = model.expiresAt
            updated.updatedAt = Date()
            if updated.userName.isEmpty { updated.userName = model.userName }
            if updated.avatarURL == nil { updated.avatarURL = model.avatarURL }
            try? await database.save(updated)
            notifyStatusesShouldRefresh()
            return
        }
        try? await database.save(model)
        notifyStatusesShouldRefresh()
    }

    func applyStoryViewedEvent(
        _ event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let dto = event.decodePayload(as: InboundStoryViewedDTO.self) else { return }

        let storyId = dto.resolvedStoryId
        let viewerId = dto.resolvedViewerId
        guard !storyId.isEmpty, !viewerId.isEmpty else { return }

        guard var segment = try? await database.fetchOne(StatusModel.self, id: storyId) else {
            return
        }

        // Only the story owner receives view notifications.
        let me = currentUserId()
        if !dto.resolvedCreatorId.isEmpty {
            guard dto.resolvedCreatorId == me else { return }
        }
        guard segment.userId == me else { return }

        let viewerQuery = QuerySpec(
            filter: FilterSpec(
                "status_id == %@ AND user_id == %@",
                .string(storyId),
                .string(viewerId)
            )
        )
        let existingViewers = (try? await database.fetch(StatusViewerModel.self, query: viewerQuery)) ?? []
        guard existingViewers.isEmpty else { return }

        let profile = await resolveStoryActorProfile(userId: viewerId, database: database)
        let viewer = StatusViewerModel(
            statusId: segment.id,
            userId: viewerId,
            contactId: profile.contactId,
            userName: profile.userName,
            avatarURL: profile.avatarURL,
            viewedAt: event.date,
            reaction: nil
        )
        try? await database.save(viewer)

        segment.viewCount += 1
        segment.updatedAt = Date()
        try? await database.save(segment)
        notifyStatusesShouldRefresh()
    }

    func applyStoryDeletedEvent(
        _ event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let dto = event.decodePayload(as: InboundStoryDeletedDTO.self) else { return }

        let storyId = dto.resolvedStoryId
        guard !storyId.isEmpty else { return }

        try? await database.deleteAll(
            StatusViewerModel.self,
            query: QuerySpec(filter: FilterSpec("status_id == %@", .string(storyId)))
        )
        try? await database.delete(StatusModel.self, id: storyId)
        notifyStatusesShouldRefresh()
    }

    func applyStoryReactedEvent(
        _ event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let dto = event.decodePayload(as: InboundStoryReactedDTO.self) else { return }

        let storyId = dto.resolvedStoryId
        let reactorId = dto.resolvedReactorId
        let reaction = dto.resolvedReaction
        guard !storyId.isEmpty, !reactorId.isEmpty, !reaction.isEmpty else { return }

        guard let segment = try? await database.fetchOne(StatusModel.self, id: storyId) else {
            return
        }

        let me = currentUserId()
        if !dto.resolvedCreatorId.isEmpty {
            guard dto.resolvedCreatorId == me else { return }
        }
        guard segment.userId == me else { return }

        let viewerQuery = QuerySpec(
            filter: FilterSpec(
                "status_id == %@ AND user_id == %@",
                .string(storyId),
                .string(reactorId)
            )
        )
        let existingViewers = (try? await database.fetch(StatusViewerModel.self, query: viewerQuery)) ?? []
        let profile = await resolveStoryActorProfile(userId: reactorId, database: database)

        if let existing = existingViewers.first {
            let updated = StatusViewerModel(
                id: existing.id,
                statusId: existing.statusId,
                userId: existing.userId,
                contactId: existing.contactId ?? profile.contactId,
                userName: existing.userName.isEmpty ? profile.userName : existing.userName,
                avatarURL: existing.avatarURL ?? profile.avatarURL,
                viewedAt: existing.viewedAt,
                reaction: reaction,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
            try? await database.save(updated)
        } else {
            // React without a prior STORY_VIEWED — still show them in the viewers list with emoji.
            let viewer = StatusViewerModel(
                statusId: segment.id,
                userId: reactorId,
                contactId: profile.contactId,
                userName: profile.userName,
                avatarURL: profile.avatarURL,
                viewedAt: event.date,
                reaction: reaction
            )
            try? await database.save(viewer)
        }

        notifyStatusesShouldRefresh()
    }

    /// Name/avatar for story viewers come from local contacts — wire payloads are IDs only.
    /// Copies `ContactModel.name` as stored (encrypted). Decrypt happens in `StatusLocalMapper.toSeenUser`.
    private func resolveStoryActorProfile(
        userId: String,
        database: any DatabaseRepositoryProtocol
    ) async -> (userName: String, avatarURL: String?, contactId: String?) {
        guard let contact = await findSyncedContact(userId: userId, phone: "", database: database) else {
            return ("", nil, nil)
        }
        let name = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = contact.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (
            name.isEmpty ? fallback : name,
            contact.avatarURL,
            contact.id
        )
    }

    func applyStoryExpiredEvent(
        _ event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let dto = event.decodePayload(as: InboundStoryExpiredDTO.self) else { return }

        let storyId = dto.resolvedStoryId
        guard !storyId.isEmpty else { return }

        try? await database.deleteAll(
            StatusViewerModel.self,
            query: QuerySpec(filter: FilterSpec("status_id == %@", .string(storyId)))
        )
        try? await database.delete(StatusModel.self, id: storyId)
        notifyStatusesShouldRefresh()
    }

    // MARK: - Outbox settlement

    /// Clears (or fails) the queued action an acknowledgement answers.
    ///
    /// The ack's `referenceId` is the same `codeMessage` the idempotency key was
    /// built from, so the two correlate exactly — no extra bookkeeping, and a
    /// replay settles the same row its first attempt created.
    private func settleOutbox(
        _ actionType: ChatOutboxItemActionType,
        event: ChatSyncEventDTO,
        acknowledged: Bool
    ) async {
        guard let outboxMaintenance,
              let reference = event.referenceId,
              !reference.isEmpty
        else { return }

        let settlement: ChatOutboxSettlement = acknowledged
            ? .acknowledged
            : .rejected(reason: serverReason(from: event) ?? "Server rejected \(event.type)")

        let settled = await outboxMaintenance.settle(
            actionType,
            reference: reference,
            as: settlement
        )

        #if DEBUG
        if settled == 0 {
            // Not a failure: an ack can answer an action sent from another device,
            // or one queued before this build.
            print("[Outbox] \(event.type) for \(reference) matched no queued \(actionType.rawValue)")
        } else {
            print("[Outbox] \(event.type) settled \(settled) \(actionType.rawValue) row(s) for \(reference)")
        }
        #endif
    }

    /// Pulls whatever explanation the server attached to a failure ack.
    private func serverReason(from event: ChatSyncEventDTO) -> String? {
        guard let data = event.payload?.rawData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        for key in ["message", "error", "reason", "errorMessage"] {
            if let value = json[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    func publishMarkDelivered(
        codeMessage: String,
        conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let realtime, let outbox else { return }
        let wireConversationId = await outboundConversationId(
            conversationId,
            database: database
        )
        await MarkDeliveredPublisher.publish(
            codeMessage: codeMessage,
            conversationId: wireConversationId,
            userId: currentUserId(),
            outbox: outbox,
            realtime: realtime
        )
    }

    func publishMarkAsRead(
        codeMessage: String,
        conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let realtime, let outbox else { return }
        let userId = currentUserId()
        guard !userId.isEmpty, !codeMessage.isEmpty else { return }
        let wireConversationId = await outboundConversationId(
            conversationId,
            database: database
        )
        await MarkAsReadPublisher.publish(
            codeMessage: codeMessage,
            userId: userId,
            conversationId: wireConversationId,
            outbox: outbox,
            realtime: realtime
        )
    }

    /// Wire id for MQTT: linked `serverId` when present, otherwise the local id.
    private func outboundConversationId(
        _ conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async -> String {
        guard !conversationId.isEmpty else { return conversationId }
        if let conversation = try? await database.fetchOne(
            ConversationModel.self,
            id: conversationId
        ) {
            return conversation.resolvedServerId
        }
        let byServer = QuerySpec(
            filter: FilterSpec("server_id == %@", .string(conversationId)),
            limit: 1
        )
        if let conversation = try? await database.fetch(
            ConversationModel.self,
            query: byServer
        ).first {
            return conversation.resolvedServerId
        }
        return conversationId
    }

    /// Acknowledges an edit to a message someone else sent.
    ///
    /// The row already existed, so the edit is a fresh reason to acknowledge it,
    /// but only the delivery half is unconditional — a read receipt is withheld
    /// for system records, whose id is a call or system id the server cannot
    /// resolve to a message.
    private func publishReceiptsForInboundEdit(
        _ existing: MessageModel,
        database: any DatabaseRepositoryProtocol
    ) async {
        await publishMarkDelivered(
            codeMessage: existing.id,
            conversationId: existing.conversationId,
            database: database
        )

        guard !existing.type.isSystemEvent,
              let conversation = try? await database.fetchOne(
                  ConversationModel.self,
                  id: existing.conversationId
              ),
              ActiveChatSessionStore.shared.isViewing(
                  conversationId: conversation.id,
                  serverId: conversation.serverId
              )
        else { return }

        await publishMarkAsRead(
            codeMessage: existing.id,
            conversationId: existing.conversationId,
            database: database
        )
    }

    /// Multi-device same-account: ACK payload carries the full message.
    /// Insert only when missing; never treat as unread — force `.sent`.
    /// Also creates the conversation (+ peer participant) when Device B never had it.
    func insertOwnMessageFromAckIfMissing(
        event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let dto = event.decodePayload(as: InboundMessageDTO.self),
              ConversationSystemRecord.kind(of: dto) == nil,
              var incoming = MessageModelMapper.toModel(from: dto, fieldCrypto: fieldCrypto) else {
            return
        }

        let existing = try? await database.fetchOne(MessageModel.self, id: incoming.id)
        guard existing == nil else { return }

        incoming.deliveryStatus = .sent

        guard let conversationId = await ensureConversation(
            for: dto,
            incoming: incoming,
            database: database
        ) else {
            return
        }

        incoming.conversationId = conversationId
        try? await database.save(incoming)

        // Own outbound ACK on another device: resolve peer from receiverId.
        if incoming.senderId == currentUserId() {
            await upsertDirectPeerParticipant(
                peerUserId: dto.receiverId ?? "",
                displayNameHint: nil,
                phoneHint: nil,
                avatarHint: nil,
                conversationId: conversationId,
                database: database,
                preferContactTitleOverSenderName: dto.senderName
            )
        }
    }

    /// Ensures the chat list can resolve the peer for a direct conversation
    /// (inbound first message, or multi-device ACK when conversation was missing).
    /// Mirrors `GRDBDiscussionDataSource.upsertDirectPeerParticipant` for the sync path.
    func upsertDirectPeerParticipant(
        peerUserId rawPeerUserId: String,
        displayNameHint: String?,
        phoneHint: String?,
        avatarHint: String?,
        conversationId: String,
        database: any DatabaseRepositoryProtocol,
        preferContactTitleOverSenderName: String? = nil
    ) async {
        let peerUserId = rawPeerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !peerUserId.isEmpty, peerUserId != currentUserId() else { return }

        // Groups resolve members elsewhere — only direct chats need this peer row.
        if let conversation = try? await database.fetchOne(ConversationModel.self, id: conversationId),
           conversation.type == .group {
            return
        }

        let hintPhone = phoneHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let contact = await findSyncedContact(
            userId: peerUserId,
            phone: hintPhone,
            database: database
        )

        let contactName = contact.map { fieldCrypto.decrypt($0.name) }
        let hintName = displayNameHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName: String = {
            if let contactName, !contactName.isEmpty { return contactName }
            if let hintName, !hintName.isEmpty { return hintName }
            return peerUserId
        }()

        let phone = {
            if let contactPhone = contact?.phone, !contactPhone.isEmpty { return contactPhone }
            return hintPhone
        }()
        let avatar = contact?.avatarURL ?? avatarHint
        let contactId = contact?.id

        let existingQuery = QuerySpec(
            filter: FilterSpec(
                "conversation_id == %@ AND user_id == %@",
                .string(conversationId),
                .string(peerUserId)
            ),
            limit: 1
        )
        if let existing = try? await database.fetch(ConversationParticipantModel.self, query: existingQuery).first {
            var updated = existing
            if updated.phone.isEmpty, !phone.isEmpty { updated.phone = phone }
            if !displayName.isEmpty {
                updated.displayName = fieldCrypto.encrypt(displayName)
            }
            if updated.avatarURL == nil { updated.avatarURL = avatar }
            if updated.contactId == nil { updated.contactId = contactId }
            updated.updatedAt = Date()
            try? await database.save(updated)
            return
        }

        let participant = ConversationParticipantModel(
            id: ackDeterministicId(from: "\(conversationId)_\(peerUserId)"),
            conversationId: conversationId,
            userId: peerUserId,
            contactId: contactId ?? ackDeterministicId(from: peerUserId),
            phone: phone,
            role: .member,
            displayName: fieldCrypto.encrypt(displayName),
            avatarURL: avatar
        )
        try? await database.save(participant)

        // Prefer peer display name as conversation title when title is empty
        // or still carrying the sender's own name (multi-device ACK case).
        if var conversation = try? await database.fetchOne(ConversationModel.self, id: conversationId),
           conversation.type == .direct {
            let currentTitle = conversation.title ?? ""
            let shouldUpdateTitle = currentTitle.isEmpty
                || (preferContactTitleOverSenderName.map { currentTitle == $0 } ?? false)
            if shouldUpdateTitle {
                conversation.title = displayName
                conversation.avatarURL = avatar ?? conversation.avatarURL
                conversation.updatedAt = Date()
                try? await database.save(conversation)
            }
        }
    }

    /// Resolves a synced contact by backend user id first, then by phone
    /// (exact match, then digits-normalized match). Phone is the practical key
    /// when the payload carries `senderPhone` and contacts were synced that way.
    func findSyncedContact(
        userId: String,
        phone: String,
        database: any DatabaseRepositoryProtocol
    ) async -> ContactModel? {
        if !userId.isEmpty {
            let byUserId = QuerySpec(
                filter: FilterSpec("user_id == %@", .string(userId)),
                limit: 1
            )
            if let contact = try? await database.fetch(ContactModel.self, query: byUserId).first {
                return contact
            }
        }

        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhone.isEmpty else { return nil }

        let byPhone = QuerySpec(
            filter: FilterSpec("phone == %@", .string(trimmedPhone)),
            limit: 1
        )
        if let contact = try? await database.fetch(ContactModel.self, query: byPhone).first {
            return contact
        }

        let targetDigits = digitsOnly(trimmedPhone)
        guard !targetDigits.isEmpty else { return nil }

        let registered = QuerySpec(
            filter: FilterSpec("is_registered == %@", .bool(true)),
            limit: 200
        )
        let contacts = (try? await database.fetch(ContactModel.self, query: registered)) ?? []
        return contacts.first { digitsOnly($0.phone) == targetDigits }
    }

    func digitsOnly(_ value: String) -> String {
        value.filter(\.isWholeNumber)
    }

    func ackDeterministicId(from string: String) -> String {
        ChatDeterministicId.uuid(from: string)
    }

    /// Clear conversation unread and publish `mark-as-read` for unread incoming messages.
    func clearUnreadAndPublishReadReceipts(
        conversationId: String?,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let conversationId,
              !conversationId.isEmpty else {
            return
        }

        // ACK / inbound events may carry the server id; local rows stay on the
        // local primary key until/unless we migrate them.
        let localConversationId = await localConversationId(
            for: conversationId,
            database: database
        )

        if var conversation = try? await database.fetchOne(
            ConversationModel.self,
            id: localConversationId
        ),
           conversation.unreadCount != 0 {
            conversation.unreadCount = 0
            conversation.updatedAt = Date()
            try? await database.save(conversation)
        }

        let myUserId = currentUserId()
        guard !myUserId.isEmpty else { return }

        let query = QuerySpec(
            filter: FilterSpec(
                "conversation_id == %@ AND sender_id != %@",
                .string(localConversationId),
                .string(myUserId)
            )
        )
        let incoming = (try? await database.fetch(MessageModel.self, query: query)) ?? []
        // System records carry a call or system id rather than a message id, so
        // the server has nothing to resolve a receipt against.
        for message in incoming
        where message.deliveryStatus != .read && !message.type.isSystemEvent {
            await publishMarkAsRead(
                codeMessage: message.id,
                conversationId: localConversationId,
                database: database
            )
            var updated = message
            updated.deliveryStatus = .read
            updated.updatedAt = Date()
            try? await database.save(updated)
        }
    }

    /// Maps a wire conversation id (local or server) back to the local row id.
    private func localConversationId(
        for conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async -> String {
        if let conversation = try? await database.fetchOne(
            ConversationModel.self,
            id: conversationId
        ) {
            return conversation.id
        }
        let byServer = QuerySpec(
            filter: FilterSpec("server_id == %@", .string(conversationId)),
            limit: 1
        )
        if let conversation = try? await database.fetch(
            ConversationModel.self,
            query: byServer
        ).first {
            return conversation.id
        }
        return conversationId
    }

    /// Multi-device ACK (`operation=MESSAGE_READ`) means another device already read this chat.
    /// Clear unread locally without publishing a second `mark-as-read`.
    func clearUnreadLocallyForReadAck(
        conversationId: String?,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let conversationId,
              !conversationId.isEmpty else {
            return
        }

        let localId = await localConversationId(for: conversationId, database: database)

        if var conversation = try? await database.fetchOne(ConversationModel.self, id: localId),
           conversation.unreadCount != 0 {
            conversation.unreadCount = 0
            conversation.updatedAt = Date()
            try? await database.save(conversation)
        }

        let myUserId = currentUserId()
        guard !myUserId.isEmpty else { return }

        let query = QuerySpec(
            filter: FilterSpec(
                "conversation_id == %@ AND sender_id != %@",
                .string(localId),
                .string(myUserId)
            )
        )
        let incoming = (try? await database.fetch(MessageModel.self, query: query)) ?? []
        for message in incoming where message.deliveryStatus != .read {
            var updated = message
            updated.deliveryStatus = .read
            updated.updatedAt = Date()
            try? await database.save(updated)
        }
    }

    func applyDeliveryStatus(
        event: ChatSyncEventDTO,
        status: MessageDeliveryStatusModel,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let messageId = event.referenceId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messageId.isEmpty,
              var existing = try? await database.fetchOne(MessageModel.self, id: messageId) else {
            return
        }
        // Deleted messages use deliveryStatus only for delete pending/ACK — ignore send receipts.
        if existing.isDeleted { return }

        // Plan SDK, étape 1.13 : du message créé sur le téléphone à l'accusé du serveur,
        // une seule fois (un second accusé trouve déjà `sent`). Une attente hors ligne
        // y est comprise : c'est ce que l'utilisateur a attendu.
        if status == .sent, existing.deliveryStatus == .pending {
            let waited = max(0, Date().timeIntervalSince(existing.timestamp))
            metricsSink.record(ChatMetric(name: ChatMetricName.sendToAck,
                                          durationMs: Int(waited * 1_000)))
        }

        existing.deliveryStatus = moreAdvancedStatus(existing.deliveryStatus, status)
        // Failed is terminal only when still pending/sent hasn't advanced past; moreAdvancedStatus
        // ranks failed lowest — force failed when ACK says so.
        if status == .failed {
            existing.deliveryStatus = .failed
        }
        // L'accusé d'envoi porte l'heure du serveur : elle remplace l'heure du
        // téléphone posée à l'envoi, pour que l'ordre du fil soit celui du
        // serveur dès l'accusé, sans attendre la prochaine synchronisation (B28).
        // Sans heure serveur, l'analyseur se replie sur l'heure de réception
        // locale — pas pire que l'heure d'envoi locale qu'elle remplace.
        if status == .sent, event.at > 0 {
            existing.timestamp = event.date
        }
        existing.updatedAt = Date()
        try? await database.save(existing)
    }

    func applyDeleteAck(
        event: ChatSyncEventDTO,
        success: Bool,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let messageId = event.referenceId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messageId.isEmpty,
              var existing = try? await database.fetchOne(MessageModel.self, id: messageId) else {
            return
        }

        let dto = event.decodePayload(as: InboundMessageDeleteDTO.self)
        // ACK payload carries `forEveryone` — never infer "for everyone" from success alone.
        let forEveryone = dto?.forEveryone ?? existing.isDeletedForAll

        existing.isDeleted = true
        existing.deletedAt = existing.deletedAt ?? Date()
        existing.searchText = nil   // legacy rows: no plaintext survives a delete
        existing.updatedAt = Date()

        if forEveryone {
            existing.isDeletedForAll = true
            // Pending clock → confirmed (or failed) for delete-for-everyone UI.
            existing.deliveryStatus = success ? .sent : .failed
            // Le contenu ne part qu'une fois la suppression confirmée (B44).
            if success {
                existing.content = Self.redactedContent(of: existing.content)
            }
        } else {
            // Delete for me: stay hidden in timeline; do not upgrade to for-everyone.
            existing.isDeletedForAll = false
        }

        try? await database.save(existing)
        if forEveryone, success {
            await redactQuotes(ofDeletedMessage: existing.id,
                               conversationId: existing.conversationId,
                               database: database)
        }
        await refreshConversationLastMessageAfterDelete(
            conversationId: existing.conversationId,
            database: database
        )
    }

    func applyModifyAck(
        event: ChatSyncEventDTO,
        success: Bool,
        database: any DatabaseRepositoryProtocol
    ) async {
        if success,
           let dto = event.decodePayload(as: BackendMessageModifiedDTO.self) {
            await applyBackendModifiedMessage(dto, fallbackEventDate: event.date, database: database)
            return
        }

        guard let messageId = event.referenceId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !messageId.isEmpty,
              var existing = try? await database.fetchOne(MessageModel.self, id: messageId) else {
            return
        }

        existing.deliveryStatus = success ? moreAdvancedStatus(existing.deliveryStatus, .sent) : .failed
        existing.updatedAt = Date()
        try? await database.save(existing)
        if success {
            try? await refreshConversationLastMessagePreview(
                conversationId: existing.conversationId,
                database: database
            )
        }
        notifyDiscussionsShouldRefresh()
    }

    func refreshConversationLastMessageAfterDelete(
        conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard var conversation = try? await database.fetchOne(ConversationModel.self, id: conversationId) else {
            return
        }

        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversationId)),
            sort: [SortSpec("timestamp", ascending: false)]
        )
        let candidates = (try? await database.fetch(MessageModel.self, query: query)) ?? []
        let last = MessageTimelineVisibility.newestVisible(in: candidates)
        if let last {
            let domain = MessageModelMapper.toDomain(last, fieldCrypto: fieldCrypto)
            conversation.lastMessageText = last.isDeleted
                ? nil
                : fieldCrypto.encryptOptional(MessageModelMapper.buildLastMessagePreview(domain))
            conversation.lastMessageType = last.type
            conversation.lastMessageSenderName = last.senderName.isEmpty ? nil : last.senderName
            conversation.lastMessageAt = last.timestamp
        } else {
            // Keep discussion row; empty preview placeholder.
            conversation.lastMessageText = nil
            conversation.lastMessageType = nil
            conversation.lastMessageSenderName = nil
            conversation.lastMessageAt = conversation.createdAt
        }
        conversation.updatedAt = Date()
        try? await database.save(conversation)
    }

    func refreshConversationLastMessagePreview(
        conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async throws {
        guard var conversation = try? await database.fetchOne(ConversationModel.self, id: conversationId) else {
            return
        }

        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversationId)),
            sort: [SortSpec("timestamp", ascending: false)]
        )
        let candidates = (try? await database.fetch(MessageModel.self, query: query)) ?? []
        let visible = MessageTimelineVisibility.newestVisible(in: candidates)

        if let visible {
            let domain = MessageModelMapper.toDomain(visible, fieldCrypto: fieldCrypto)
            conversation.lastMessageText = visible.isDeleted
                ? nil
                : fieldCrypto.encryptOptional(MessageModelMapper.buildLastMessagePreview(domain))
            conversation.lastMessageType = visible.type
            conversation.lastMessageSenderName = visible.senderName.isEmpty ? nil : visible.senderName
            conversation.lastMessageAt = visible.timestamp
        } else {
            conversation.lastMessageText = nil
            conversation.lastMessageType = nil
            conversation.lastMessageSenderName = nil
            conversation.lastMessageAt = conversation.createdAt
        }

        conversation.updatedAt = Date()
        try? await database.save(conversation)
    }

    /// Applies backend `MESSAGE_DELIVERED` (`InboundDeliveryReceiptDTO`):
    /// advances aggregated ticks + upserts per-user `ReadReceiptModel.deliveredAt`.
    func applyInboundDeliveryReceipt(
        event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        let dto = event.decodePayload(as: InboundDeliveryReceiptDTO.self)
            ?? fallbackDeliveryReceiptDTO(from: event)
        guard let dto else { return }

        let codeMessage = dto.codeMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !codeMessage.isEmpty,
              var message = try? await database.fetchOne(MessageModel.self, id: codeMessage) else {
            return
        }

        if message.isDeleted { return }

        message.deliveryStatus = moreAdvancedStatus(message.deliveryStatus, .delivered)
        message.updatedAt = Date()
        try? await database.save(message)

        let peerUserId = dto.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !peerUserId.isEmpty else { return }

        let conversationId = dto.conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? message.conversationId
            : dto.conversationId
        let deliveredAt = dto.deliveredDate ?? event.date

        let existingQuery = QuerySpec(
            filter: FilterSpec(
                "message_id == %@ AND user_id == %@",
                .string(codeMessage),
                .string(peerUserId)
            ),
            limit: 1
        )
        if var existing = try? await database.fetch(ReadReceiptModel.self, query: existingQuery).first {
            if existing.deliveredAt == nil || (existing.deliveredAt ?? .distantFuture) > deliveredAt {
                existing.deliveredAt = deliveredAt
            }
            existing.updatedAt = Date()
            try? await database.save(existing)
            return
        }

        let receipt = ReadReceiptModel(
            id: ackDeterministicId(from: "\(codeMessage)_\(peerUserId)_delivered"),
            messageId: codeMessage,
            conversationId: conversationId,
            userId: peerUserId,
            deliveredAt: deliveredAt
        )
        try? await database.save(receipt)
    }

    func fallbackDeliveryReceiptDTO(from event: ChatSyncEventDTO) -> InboundDeliveryReceiptDTO? {
        guard let codeMessage = event.referenceId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !codeMessage.isEmpty else {
            return nil
        }
        return InboundDeliveryReceiptDTO(
            codeMessage: codeMessage,
            conversationId: event.conversationId ?? "",
            userId: "",
            deliveredAt: Int64(event.at * 1_000)
        )
    }

    /// ACK may include oldConversationId → set ConversationModel.serverId = conversationId.
    /// Only links when `oldConversationId` is present AND `serverId` is still nil
    /// (never overwrite an existing serverId).
    func linkConversationServerIdIfNeeded(
        event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let raw = event.payload?.rawData,
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            return
        }
        let oldId = (json["oldConversationId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let backendId = (json["conversationId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let oldId, !oldId.isEmpty,
              let backendId, !backendId.isEmpty,
              var conversation = try? await database.fetchOne(ConversationModel.self, id: oldId) else {
            return
        }

        // Already linked — do not overwrite what exists.
        if conversation.serverId != nil {
            return
        }

        conversation.serverId = backendId
        conversation.updatedAt = Date()
        try? await database.save(conversation)
    }

    /// Ensures a conversation row exists for FK.
    /// `serverId` remapping is ACK-driven only via `linkConversationServerIdIfNeeded`.
    /// Returns the local conversation ID to use on the message.
    func ensureConversation(
        for dto: InboundMessageDTO,
        incoming: MessageModel,
        database: any DatabaseRepositoryProtocol
    ) async -> String? {
        
        guard let backendConversationId = dto.conversationId, !backendConversationId.isEmpty else {
            return nil
        }

        let isFromOtherUser = incoming.senderId != currentUserId()
        // Not even as the first thing in a brand new conversation — an empty group
        // reads as empty, which is what it is.
        let preview: String? = {
            guard ConversationPreviewPolicy.updatesPreview(dto) else {
                return nil
            }
            if incoming.isViewOnce { return "⏱ View once message" }
            let text = dto.messageContent.text ?? ""
            return text.isEmpty
                ? lastMessagePreview(for: incoming.type, content: dto.content)
                : text
        }()

        var conversation: ConversationModel?

        if conversation == nil {
            let query = QuerySpec(
                filter: FilterSpec("server_id == %@", .string(backendConversationId)),
                limit: 1
            )
            // Also by primary key, not just `server_id`: a conversation this device
            // created is stored under its local id and has no `server_id` until the
            // create call comes back. For a group the backend keys its traffic on the
            // id we supplied at creation, so the echo arrives naming a row that is
            // already here — and matching on `server_id` alone misses it, leaving the
            // branch below to rebuild that same id with no title and no avatar.
            var stored = try? await database.fetch(ConversationModel.self, query: query).first
            if stored == nil {
                stored = try? await database.fetchOne(
                    ConversationModel.self,
                    id: backendConversationId
                )
            }
            // A row merged into another still receives traffic under its own
            // id — the server never stopped listing it. Follow the pointer so
            // the message lands in the thread the inbox actually shows.
            stored = await ConversationAliasResolver.resolved(stored, in: database)

            // Still nothing, and this is a direct message? Then ask by peer
            // before creating anything. A chat started on this device carries no
            // server id until an ACK links one, so the two lookups above miss it
            // and this branch is where the inbox grew a second row for someone
            // already in it.
            //
            // Gated on `hasDirectPeerSignal`, not just `!isGroupConversation`:
            // `isGroupConversation` returning false only means "no groupId" — it
            // does not mean "is a DM". A BROADCAST/channel post has neither a
            // `groupId` (that is a GROUP concept in Core, not a channel one) nor
            // a `receiverId` (nobody in particular receives a broadcast), so
            // without this guard every such post was looked up — and merged —
            // by sender id as if it were a 1:1 message from the channel owner.
            if stored == nil, !isGroupConversation(dto), hasDirectPeerSignal(dto) {
                let peerId = isFromOtherUser
                    ? incoming.senderId
                    : (dto.receiverId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                if !peerId.isEmpty {
                    stored = await DirectConversationLookup.unlinked(peerUserId: peerId, in: database)
                }
            }

            if var existing = stored {
                if existing.serverId == nil {
                    existing.serverId = backendConversationId
                }
                // Backfill for rows written before the group id was kept.
                if existing.groupId == nil, let groupId = payloadGroupId(dto) {
                    existing.groupId = groupId
                }
                // The server just sent us traffic for this group, so it exists on
                // the server whatever this row last claimed.
                if existing.type == .group,
                   !GroupMapper.isSyncedMetadata(existing.assignedAgentName) {
                    // `existing` matters here: a group this device created carries
                    // its creator in metadata the server echo cannot restate, and
                    // rewriting it from a payload that names nobody used to erase
                    // the creator from their own group.
                    existing.assignedAgentName = syncedGroupMetadata(
                        for: dto,
                        existingMetadata: existing.assignedAgentName
                    )
                }
                // Repair rows wrongly typed as .group when the payload is clearly
                // a DM — `hasDirectPeerSignal` again, so an ambiguous broadcast
                // payload can never bounce an already-mistyped channel row from
                // `.group` to `.direct` on top of its existing mistyping.
                if existing.type == .group, !isGroupConversation(dto), hasDirectPeerSignal(dto) {
                    existing.type = .direct
                }
                conversation = existing
            } else {
                let isGroup = isGroupConversation(dto)
                // Neither a group id nor a direct-peer signal: per this file's own
                // contract a DM always carries `receiverId`, so this payload is
                // *not* a direct message — most likely a channel/broadcast post,
                // which gets no `groupId` from Core. `.group` is the closest type
                // this row can honestly claim until `ChannelRoomViewModel` (or a
                // correctly-typed REST inbox sync) retypes it `.channel`; `.direct`
                // would be a false claim the peer lookup above no longer risks.
                let isDirect = !isGroup && hasDirectPeerSignal(dto)
                let isOwnMessage = !isFromOtherUser
                // For own ACKs (multi-device), peer title is filled later via receiverId lookup.
                let title: String? = {
                    if !isDirect { return nil }
                    if isOwnMessage { return nil }
                    return dto.senderName.isEmpty ? nil : dto.senderName
                }()
                conversation = ConversationModel(
                    id: backendConversationId,
                    serverId: backendConversationId,
                    groupId: isGroup ? payloadGroupId(dto) : nil,
                    type: isDirect ? .direct : .group,
                    title: title,
                    avatarURL: isOwnMessage ? nil : dto.senderAvatar,
                    lastMessageText: fieldCrypto.encryptOptional(preview),
                    lastMessageType: incoming.type,
                    lastMessageSenderName: dto.senderName.isEmpty ? nil : fieldCrypto.encrypt(dto.senderName),
                    lastMessageAt: incoming.timestamp,
                    unreadCount: 0,
                    assignedAgentName: isGroup ? syncedGroupMetadata(for: dto) : nil,
                    createdAt: incoming.timestamp,
                    updatedAt: Date()
                )
            }
        }

        guard var resolved = conversation else { return nil }

        applyLastMessagePreview(
            to: &resolved,
            from: incoming,
            dto: dto,
            preview: preview,
            isFromOtherUser: isFromOtherUser
        )
        do {
            try await database.save(resolved)
            debugLog("saved conversation \(resolved.id)", category: "chat-sync")
            return resolved.id
        } catch {
            debugLog("failed to save conversation: \(error)", category: "chat-sync")
            return nil
        }
    }

    /// Sync metadata for a group conversation built from an inbound payload.
    ///
    /// A group this device learns about *from the server* is synced the moment it
    /// is created — it is not a local draft awaiting confirmation. The discussion
    /// list filters group conversations on exactly this, so creating one without
    /// it stores the group correctly and then hides it.
    /// `existingMetadata` is what the row already says, and is never overwritten
    /// with a blank: most payloads name no creator at all, so a group would lose the
    /// one it had the first time an ordinary message arrived in it.
    func syncedGroupMetadata(
        for dto: InboundMessageDTO,
        existingMetadata: String? = nil
    ) -> String {
        let event = dto.resolvedGroupEvent
        let storedCreator = GroupMapper.createdBy(in: existingMetadata)
        let createdBy: String = {
            if event?.type == .GROUP_CREATED, let actorId = event?.actorId, !actorId.isEmpty {
                return actorId
            }
            // Any later event only carries whoever it affected, so the creator is
            // recoverable only when the roster happens to name an owner.
            let owner = event?.targets.first { $0.participantRole == .owner }?.userId ?? ""
            return owner.isEmpty ? storedCreator : owner
        }()
        return GroupMapper.syncedMetadata(
            createdBy: createdBy,
            color: GroupMapper.color(in: existingMetadata)
        )
    }

    /// The group id the payload carries, if it carries one.
    ///
    /// Kept rather than inferred from `conversationId`: outbound messages have
    /// their own `groupId` field and the group endpoints take a group id, so
    /// throwing it away here would mean guessing it back everywhere else.
    func payloadGroupId(_ dto: InboundMessageDTO) -> String? {
        let groupId = dto.groupId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return groupId.isEmpty ? nil : groupId
    }

    /// A positive signal that this payload names a 1:1 peer.
    ///
    /// The only thing that makes it safe to look this message up — or type a
    /// new row — as a direct conversation. `!isGroupConversation(dto)` is not
    /// that signal: it is true both for a real DM and for a payload naming
    /// neither a group nor a peer, which is what a BROADCAST/channel post
    /// looks like (Core gives it no `groupId`, and nobody in particular
    /// receives a broadcast, so no `receiverId` either).
    func hasDirectPeerSignal(_ dto: InboundMessageDTO) -> Bool {
        !(dto.receiverId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    /// Direct messages carry `receiverId`. A non-empty `groupId` alone is not enough —
    /// backends often leave a spurious `groupId` on DM payloads.
    func isGroupConversation(_ dto: InboundMessageDTO) -> Bool {
        let groupId = dto.groupId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let receiverId = dto.receiverId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !receiverId.isEmpty {
            return false
        }
        return !groupId.isEmpty
    }

    func applyLastMessagePreview(
        to conversation: inout ConversationModel,
        from message: MessageModel,
        dto: InboundMessageDTO,
        preview: String?,
        isFromOtherUser: Bool
    ) {
        guard ConversationPreviewPolicy.updatesPreview(dto) else {
            return
        }

        if let lastAt = conversation.lastMessageAt, message.timestamp < lastAt {
            return
        }

        conversation.lastMessageText = fieldCrypto.encryptOptional(preview)
        conversation.lastMessageType = message.type
        conversation.lastMessageSenderName = dto.senderName.isEmpty ? nil : fieldCrypto.encrypt(dto.senderName)
        conversation.lastMessageAt = message.timestamp
        conversation.updatedAt = Date()
        if isFromOtherUser,
           !ActiveChatSessionStore.shared.isViewing(
               conversationId: conversation.id,
               serverId: conversation.serverId
           ) {
            conversation.unreadCount += 1
        }
    }

    func lastMessagePreview(for type: MessageTypeModel, content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == .text, !trimmed.isEmpty { return trimmed }
        switch type {
        case .image: return "📷 Photo"
        case .video: return "🎥 Video"
        case .videoNote: return "🎥 Video note"
        case .audio, .voice: return "🎵 Audio"
        case .document: return "📄 Document"
        case .location: return "📍 Location"
        case .contact: return "👤 Contact"
        case .payment: return "💰 Payment"
        default: return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// A conversation system record becomes a checkpoint, as the history sync
    /// does it, or nothing at all.
    private func saveSystemRecordCheckpoint(
        _ dto: InboundMessageDTO,
        kind: ConversationSystemRecord.Kind,
        conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let action = ConversationSystemRecord.checkpoint(
            for: dto,
            kind: kind,
            conversationId: conversationId
        ) else { return }
        do {
            try await database.save(ChatActionMapper().toGRDB(action))
        } catch {
            debugLog("system record checkpoint not saved: \(error)", category: "chat-sync")
        }
    }

    func mergeIncomingMessage(existing: MessageModel?, incoming: MessageModel) -> MessageModel {
        var merged = incoming

        if incoming.senderId == currentUserId() {
            merged.deliveryStatus = moreAdvancedStatus(existing?.deliveryStatus, .sent)
        }

        guard let existing else { return merged }

        merged.deliveryStatus = moreAdvancedStatus(existing.deliveryStatus, merged.deliveryStatus)
        merged.createdAt = existing.createdAt
        merged.updatedAt = Date()

        if merged.content.localPath == nil {
            merged.content.localPath = existing.content.localPath
        }
        if merged.content.pendingUpload == nil {
            merged.content.pendingUpload = existing.content.pendingUpload
        }
        if merged.content.mediaBatchId == nil {
            merged.content.mediaBatchId = existing.content.mediaBatchId
        }
        // The server has no opinion on whether this device's upload failed, so an
        // echo of the message must not erase what we learned locally.
        if merged.content.mediaTransferFailed == nil {
            merged.content.mediaTransferFailed = existing.content.mediaTransferFailed
        }
        // A view-once message this device has used up stays used up. The server
        // still holds the original, so an echo of it must not bring back the
        // content that was wiped — the same rule as for deletes below (B44).
        if existing.content.viewOnceOpenedAt != nil {
            merged.isViewOnce = true
            merged.content = existing.content
            merged.searchText = nil
        }
        // Aucun événement ne « dé-supprime » un message : un écho serveur du
        // contenu d'origine ne le fait pas réapparaître (B44).
        if existing.isDeleted {
            merged.isDeleted = true
            merged.deletedAt = existing.deletedAt
            merged.isDeletedForAll = existing.isDeletedForAll || merged.isDeletedForAll
            merged.searchText = nil   // legacy rows: no plaintext survives a delete
            // Le contenu renvoyé est celui d'avant la suppression : on garde le
            // nôtre, vidé si la suppression pour tous est confirmée (B44).
            merged.content = existing.content
        }
        // Le serveur renvoie la citation telle qu'envoyée ; une suppression
        // pour tous apprise depuis ne se défait pas sur un écho (B44).
        if existing.replyToIsDeleted == true {
            merged = Self.redactingQuote(of: merged)
        }

        return merged
    }

    /// Ce qu'un message reçu devient une fois fusionné avec ce que l'appareil
    /// sait déjà — dont une réponse arrivée après la suppression pour tous de
    /// l'original, qui ne doit pas réapporter le texte supprimé (B44).
    func mergedForSave(
        _ incoming: MessageModel,
        database: any DatabaseRepositoryProtocol
    ) async -> (existing: MessageModel?, model: MessageModel) {
        let existing = try? await database.fetchOne(MessageModel.self, id: incoming.id)
        var model = mergeIncomingMessage(existing: existing, incoming: incoming)
        if model.replyToIsDeleted != true,
           let quotedId = model.replyToMessageId, !quotedId.isEmpty,
           let quoted = try? await database.fetchOne(MessageModel.self, id: quotedId),
           quoted.isDeletedForAll {
            model = Self.redactingQuote(of: model)
        }
        return (existing, model)
    }

    /// Ce qu'un message supprimé pour tous garde de son contenu (B44) : le lot
    /// média, qui regroupe les bulles d'un envoi multiple, et les références
    /// financières, qui appartiennent au serveur. Texte, fichiers, position,
    /// contacts, sondage et le reste partent.
    static func redactedContent(of content: MessageContentModel) -> MessageContentModel {
        var kept = MessageContentModel()
        kept.mediaBatchId = content.mediaBatchId
        kept.paymentAmount = content.paymentAmount
        kept.paymentCurrency = content.paymentCurrency
        kept.paymentStatus = content.paymentStatus
        kept.paymentRef = content.paymentRef
        kept.paymentAmountDecimal = content.paymentAmountDecimal
        kept.financialObjectType = content.financialObjectType
        kept.financialObjectVersion = content.financialObjectVersion
        kept.financialCorrelationId = content.financialCorrelationId
        kept.financialCounterpartyName = content.financialCounterpartyName
        kept.financialFeeAmount = content.financialFeeAmount
        kept.financialFeeAmountDecimal = content.financialFeeAmountDecimal
        kept.financialVerification = content.financialVerification
        kept.financialRefreshedAt = content.financialRefreshedAt
        return kept
    }

    /// Vide la copie du message cité et marque la citation comme supprimée (B44).
    static func redactingQuote(of message: MessageModel) -> MessageModel {
        var redacted = message
        redacted.replyToIsDeleted = true
        redacted.replyToMessagePreview = nil
        redacted.replyToThumbnailURL = nil
        return redacted
    }

    /// Les réponses qui citent `messageId` perdent leur copie du texte cité.
    /// Une réponse cite un message de sa propre conversation ; `replyToMessageId`
    /// n'étant pas une colonne, le filtre se fait en mémoire.
    func redactQuotes(ofDeletedMessage messageId: String,
                      conversationId: String,
                      database: any DatabaseRepositoryProtocol) async {
        let query = QuerySpec(filter: FilterSpec("conversation_id == %@", .string(conversationId)))
        let messages = (try? await database.fetch(MessageModel.self, query: query)) ?? []
        for reply in messages where reply.replyToMessageId == messageId && reply.replyToIsDeleted != true {
            var redacted = Self.redactingQuote(of: reply)
            redacted.updatedAt = Date()
            try? await database.save(redacted)
        }
    }

    func applyModifiedMessageEvent(
        _ event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        if let dto = event.decodePayload(as: BackendMessageModifiedDTO.self) {
            await applyBackendModifiedMessage(dto, fallbackEventDate: event.date, database: database)
            return
        }

        if let legacy = event.decodePayload(as: InboundMessageEditDTO.self) {
            await applyLegacyModifiedMessage(legacy, fallbackEventDate: event.date, database: database)
        }
    }

    func applyBackendModifiedMessage(
        _ dto: BackendMessageModifiedDTO,
        fallbackEventDate: Date,
        database: any DatabaseRepositoryProtocol
    ) async {
        let messageId = dto.codeMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageId.isEmpty,
              var existing = try? await database.fetchOne(MessageModel.self, id: messageId) else {
            return
        }

        let content = dto.messageContent
        existing.content = MessageModelMapper.mapInboundContent(
            content,
            type: existing.type,
            fieldCrypto: fieldCrypto
        )
        existing.isEdited = true
        existing.editedAt = dto.resolvedEditedAt ?? existing.editedAt ?? fallbackEventDate
        existing.updatedAt = Date()

        let isOwnEdit = dto.senderId == currentUserId()
        if isOwnEdit {
            existing.deliveryStatus = moreAdvancedStatus(existing.deliveryStatus, .sent)
        }

        try? await database.save(existing)
        try? await refreshConversationLastMessagePreview(
            conversationId: existing.conversationId,
            database: database
        )

        if !isOwnEdit {
            await publishReceiptsForInboundEdit(existing, database: database)
        }

        notifyDiscussionsShouldRefresh()
    }

    func applyLegacyModifiedMessage(
        _ dto: InboundMessageEditDTO,
        fallbackEventDate: Date,
        database: any DatabaseRepositoryProtocol
    ) async {
        let messageId = dto.messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageId.isEmpty,
              var existing = try? await database.fetchOne(MessageModel.self, id: messageId) else {
            return
        }

        existing.content = MessageModelMapper.mapInboundContent(
            dto.newContent,
            type: existing.type,
            fieldCrypto: fieldCrypto
        )
        existing.isEdited = true
        existing.editedAt = Date(timeIntervalSince1970: dto.editedAt > 10_000_000_000 ? dto.editedAt / 1000 : dto.editedAt)
        existing.updatedAt = Date()

        let isOwnEdit = dto.userId == currentUserId()
        if isOwnEdit {
            existing.deliveryStatus = moreAdvancedStatus(existing.deliveryStatus, .sent)
        }

        try? await database.save(existing)
        try? await refreshConversationLastMessagePreview(
            conversationId: existing.conversationId,
            database: database
        )

        if !isOwnEdit {
            await publishReceiptsForInboundEdit(existing, database: database)
        }

        notifyDiscussionsShouldRefresh()
    }

    /// Applies a vote to the poll stored on the message.
    ///
    /// Unlike a reaction, which has its own table, a vote lives inside the
    /// message's content blob — so this reads the row, rewrites the blob and
    /// saves, the same shape the delete branch uses.
    ///
    /// The echo of the local user's own vote lands here too and must change
    /// nothing: `PollVoteMerger` is idempotent, so the optimistic write and the
    /// server's confirmation converge instead of double-counting.
    func applyInboundPollVoteEvent(
        _ event: ChatSyncEventDTO,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let dto = event.decodePayload(as: InboundPollVoteDTO.self) else { return }

        let fallbackId = event.referenceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let messageId = dto.resolvedCodeMessage.isEmpty ? fallbackId : dto.resolvedCodeMessage
        guard !messageId.isEmpty else { return }

        // A vote for a message this device never stored. Same outcome as an
        // inbound reaction for an unknown message: nothing to patch.
        guard var message = try? await database.fetchOne(MessageModel.self, id: messageId),
              let existing = message.content.pollOptions,
              !existing.isEmpty
        else { return }

        let updatedOptions: [PollOptionModel]

        if let authoritative = dto.pollOptions, !authoritative.isEmpty {
            // The server sent the whole tally — it outranks anything computed here.
            updatedOptions = authoritative.map {
                PollOptionModel(
                    id: $0.id,
                    text: $0.text,
                    voterIds: $0.voterIds ?? [],
                    voteCount: $0.voteCount ?? ($0.voterIds?.count ?? 0)
                )
            }
        } else {
            guard !dto.resolvedVoterId.isEmpty else { return }

            let current = PollContent(
                question: message.content.pollQuestion ?? "",
                options: existing.map {
                    PollOption(
                        id: $0.id,
                        text: $0.text,
                        voterIds: $0.voterIds,
                        voteCount: $0.voteCount
                    )
                },
                isMultipleChoice: message.content.pollIsMultipleChoice ?? false
            )

            let merged: PollContent
            if let selection = dto.resolvedSelection {
                // A whole selection, which is the only shape that can say
                // "nothing" — an empty array is a retraction, not a no-op.
                merged = PollVoteMerger.applySelection(
                    selection,
                    voterId: dto.resolvedVoterId,
                    to: current
                )
            } else {
                guard !dto.resolvedOptionId.isEmpty else { return }
                merged = PollVoteMerger.apply(
                    optionId: dto.resolvedOptionId,
                    voterId: dto.resolvedVoterId,
                    to: current
                )
            }

            updatedOptions = merged.options.map {
                PollOptionModel(
                    id: $0.id,
                    text: $0.text,
                    voterIds: $0.voterIds,
                    voteCount: $0.voteCount
                )
            }
        }

        message.content.pollOptions = updatedOptions
        message.updatedAt = Date()
        try? await database.save(message)
    }

    func applyInboundReactionEvent(
        _ event: ChatSyncEventDTO,
        removing: Bool,
        database: any DatabaseRepositoryProtocol
    ) async {
      
        let backend = event.decodePayload(as: BackendMessageReactionEventDTO.self)
        let simplified = event.decodePayload(as: InboundReactMessageDTO.self)
            ?? legacyInboundReactionDTO(from: event)

        let messageId: String
        let rawUserId: String?
        let rawSenderId: String?
        let emoji: String
        let reactedAt: Date?
        let shouldRemove: Bool

        if let backend {
            messageId = backend.resolvedCodeMessage
            rawUserId = backend.userId
            rawSenderId = backend.senderId
            emoji = backend.resolvedReaction
            reactedAt = backend.resolvedReactedAt ?? event.date
            shouldRemove = removing || backend.isRemovalEvent
        } else if let simplified {
            messageId = simplified.codeMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            rawUserId = simplified.userId
            rawSenderId = nil
            emoji = simplified.reaction.trimmingCharacters(in: .whitespacesAndNewlines)
            reactedAt = event.date
            shouldRemove = removing || simplified.isRemoval
        } else {
            #if DEBUG
            print("[Reaction] inbound decode failed type=\(event.type) ref=\(event.referenceId ?? "nil")")
            #endif
            return
        }

        let fallbackMessageId = event.referenceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedMessageId = messageId.isEmpty ? fallbackMessageId : messageId
        guard !resolvedMessageId.isEmpty else {
            #if DEBUG
            print("[Reaction] missing codeMessage for inbound event")
            #endif
            return
        }

        let localMessage = try? await database.fetchOne(MessageModel.self, id: resolvedMessageId)
        let userId = MessageReactionIdentity.resolveReactor(
            userId: rawUserId,
            senderId: rawSenderId,
            messageAuthorId: localMessage?.senderId
        )

        guard !userId.isEmpty else {
            #if DEBUG
            print("[Reaction] missing reactor id for messageId=\(resolvedMessageId)")
            #endif
            return
        }

        #if DEBUG
        print(
            "[Reaction] inbound remove=\(shouldRemove) messageId=\(resolvedMessageId) reactor=\(userId) author=\(localMessage?.senderId ?? "missing") emoji=\(emoji) localMessageFound=\(localMessage != nil)"
        )
        #endif

        let query = QuerySpec(
            filter: FilterSpec(
                "message_id == %@ AND user_id == %@",
                .string(resolvedMessageId),
                .string(userId)
            ),
            limit: 1
        )

        if shouldRemove {
            if let existing = try? await database.fetch(MessageReactionModel.self, query: query).first {
                do {
                    try await database.delete(MessageReactionModel.self, id: existing.id)
                } catch {
                    #if DEBUG
                    print("[Reaction] delete failed: \(error)")
                    #endif
                }
            }
            await touchMessageForReactionObservation(messageId: resolvedMessageId, database: database)
            return
        }

        guard !emoji.isEmpty else {
            #if DEBUG
            print("[Reaction] ADDED ignored — empty emoji messageId=\(resolvedMessageId)")
            #endif
            return
        }

        guard localMessage != nil else {
            #if DEBUG
            print("[Reaction] skip save — no local MessageModel id=\(resolvedMessageId) (FK would fail)")
            #endif
            return
        }

        let timestamp = reactedAt ?? Date()

        do {
            if var existing = try await database.fetch(MessageReactionModel.self, query: query).first {
                existing.emoji = emoji
                existing.updatedAt = timestamp
                try await database.save(existing)
            } else {
                let model = MessageReactionModel(
                    messageId: resolvedMessageId,
                    userId: userId,
                    userName: "",
                    emoji: emoji,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
                try await database.save(model)
            }
        } catch {
            #if DEBUG
            print("[Reaction] save failed messageId=\(resolvedMessageId) reactor=\(userId): \(error)")
            #endif
            return
        }

        await touchMessageForReactionObservation(messageId: resolvedMessageId, database: database)
    }

    /// Ensures active chat rooms re-observe after reaction table changes.
    private func touchMessageForReactionObservation(
        messageId: String,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard var message = try? await database.fetchOne(MessageModel.self, id: messageId) else {
            #if DEBUG
            print("[Reaction] touch skipped — message missing id=\(messageId)")
            #endif
            return
        }
        message.updatedAt = Date()
        do {
            try await database.save(message)
        } catch {
            #if DEBUG
            print("[Reaction] touch save failed id=\(messageId): \(error)")
            #endif
        }
    }

    func legacyInboundReactionDTO(from event: ChatSyncEventDTO) -> InboundReactMessageDTO? {
        guard let legacy = event.decodePayload(as: InboundReactionDTO.self) else { return nil }
        let messageId = legacy.messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageId.isEmpty else { return nil }
        let removing = legacy.action.lowercased() == "remove"
        return InboundReactMessageDTO(
            userId: legacy.userId,
            conversationId: legacy.conversationId,
            codeMessage: messageId,
            reaction: removing ? "" : legacy.emoji
        )
    }

    func applyFlushResult(
        _ result: OutboxFlushResult,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard let item = try? await database.fetchOne(ChatOutboxItem.self, id: result.localId),
              let messageId = messageIdForFlushResult(item: item) else {
            return
        }
        guard !messageId.isEmpty,
              var message = try? await database.fetchOne(MessageModel.self, id: messageId) else {
            return
        }

        if result.success {
            message.deliveryStatus = moreAdvancedStatus(message.deliveryStatus, .sent)
            if let serverTimestamp = result.serverTimestamp {
                message.timestamp = serverTimestamp
            }
        } else if !result.isRetryable {
            message.deliveryStatus = .failed
        }

        message.updatedAt = Date()
        try? await database.save(message)
        notifyDiscussionsShouldRefresh()
    }

    private func messageIdForFlushResult(item: ChatOutboxItem) -> String? {
        switch item.actionType {
        case .sendMessage:
            return (try? JSONDecoder().decode(OutboundMessageDTO.self, from: item.payload))?
                .codeMessage
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .modifyMessage:
            return (try? JSONDecoder().decode(OutboundModifyMessageDTO.self, from: item.payload))?
                .codeMessage
                .trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return nil
        }
    }

    func moreAdvancedStatus(
        _ lhs: MessageDeliveryStatusModel?,
        _ rhs: MessageDeliveryStatusModel
    ) -> MessageDeliveryStatusModel {
        guard let lhs else { return rhs }
        return statusRank(lhs) >= statusRank(rhs) ? lhs : rhs
    }

    func statusRank(_ status: MessageDeliveryStatusModel) -> Int {
        switch status {
        case .failed: return 0
        case .pending: return 1
        case .sent: return 2
        case .delivered: return 3
        case .read: return 4
        }
    }
}
