import Foundation
import WaanguCoreKit

class DiscussionRepository: DiscussionRepositoryProtocol {

    private let localDataSource: LocalDiscussionDataSourceProtocol
    private let remoteConversationSyncDataSource: RemoteConversationSyncDataSourceProtocol
    private let database: any DatabaseRepositoryProtocol
    private let syncCursorStore: SyncCursorStore
    private let fieldCrypto: any FieldEncryptionServiceProtocol
    private let chatActionsDataSource: LocalChatActionsDataSourceProtocol

    /// Bloc 8, §39 — les échecs de synchronisation laissent une trace, y
    /// compris en RELEASE où les `print` disparaissaient.
    private let telemetry: any SyncTelemetryEmitting

    /// Nom de flux pour la télémétrie.
    private static let conversationsStream = "chat_conversations"

    /// Bloc 8, §33 — un appareil révoqué ne synchronise pas.
    private let revocationGuard: any DeviceRevocationChecking

    /// Identité de cet appareil, pour interroger le garde.
    private let deviceInfoProvider: any DeviceInfoProvidingProtocol

    init(
        localDataSource: LocalDiscussionDataSourceProtocol,
        remoteConversationSyncDataSource: RemoteConversationSyncDataSourceProtocol,
        database: any DatabaseRepositoryProtocol,
        syncCursorStore: SyncCursorStore,
        fieldCrypto: any FieldEncryptionServiceProtocol,
        chatActionsDataSource: LocalChatActionsDataSourceProtocol,
        // Défaut muet plutôt qu'optionnel : un appelant qui doit écrire
        // `telemetry?.emit(...)` finit par en oublier un.
        telemetry: any SyncTelemetryEmitting = NoOpSyncTelemetry(),
        revocationGuard: any DeviceRevocationChecking = AllowAllDeviceRevocation(),
        deviceInfoProvider: any DeviceInfoProvidingProtocol
    ) {
        self.localDataSource = localDataSource
        self.remoteConversationSyncDataSource = remoteConversationSyncDataSource
        self.database = database
        self.syncCursorStore = syncCursorStore
        self.fieldCrypto = fieldCrypto
        self.chatActionsDataSource = chatActionsDataSource
        self.telemetry = telemetry
        self.revocationGuard = revocationGuard
        self.deviceInfoProvider = deviceInfoProvider
    }

    func fetchDiscussions() async throws -> [DiscussionChatItem] {
        try await localDataSource.fetchDiscussions()
    }

    func deduplicateConversationsIfNeeded() async {
        await ConversationDeduplicationService(database: database).runIfNeeded()
    }

    func getDiscussionById(conversationId: String) async throws -> DiscussionChatItem? {
        let discussions = try await localDataSource.fetchDiscussions()
        return discussions.first { $0.conversationId == conversationId }
    }

    func saveDiscussion(_ discussion: DiscussionChatItem) async throws {
        try await localDataSource.saveDiscussion(discussion)
    }

    func updateDiscussionSetting(_ discussion: DiscussionChatItem) async throws {
        try await localDataSource.updateDiscussionSetting(discussion)
    }

    func fetchMessages(_ conversationId: String) async throws -> [MessageDataItem] {
        try await localDataSource.fetchMessages(conversationId)
    }

    func fetchMessagesWithPagination(
        conversationId: String,
        before cursor: Date?,
        pageSize: Int
    ) async throws -> [MessageDataItem] {
        try await localDataSource.fetchMessagesWithPagination(
            conversationId: conversationId,
            before: cursor,
            pageSize: pageSize
        )
    }

    func deleteDiscussion(conversationId: String) async throws {
        try await localDataSource.deleteDiscussion(conversationId: conversationId)
    }

    func deleteAllDiscussionMessages(conversationId: String) async throws {
        try await localDataSource.deleteAllDiscussionMessages(conversationId: conversationId)
    }

    func clearUnreadCount(conversationId: String) async throws {
        try await localDataSource.clearUnreadCount(conversationId: conversationId)
    }

    func saveDraft(conversationId: String, text: String) async throws {
        try await localDataSource.saveDraft(conversationId: conversationId, text: text)
    }

    func fetchDraft(conversationId: String) async throws -> String? {
        try await localDataSource.fetchDraft(conversationId: conversationId)
    }

    func outboundConversationId(for localConversationId: String) async -> String {
        await localDataSource.outboundConversationId(for: localConversationId)
    }

    func outboundGroupId(for localConversationId: String) async -> String? {
        await localDataSource.outboundGroupId(for: localConversationId)
    }
    
    // MARK: - Sync
    
    func syncConversations(since: Date?, limit: Int) async throws -> ConversationSyncResult {
        // Bloc 8, §33 — REVOKED_DEVICE_CANNOT_SYNC_SENSITIVE_DATA.
        //
        // Avant la première requête, pas après : la révocation doit empêcher la
        // donnée d'arriver, pas seulement son écriture.
        do {
            try await revocationGuard.validateNotRevoked(
                deviceId: deviceInfoProvider.captureDeviceContext().deviceId
            )
        } catch {
            await telemetry.emit(.deviceRevoked(deviceIDHash: ""))
            throw error
        }

        var allConversationIds: [String] = []
        var totalCreated = 0
        var totalUpdated = 0
        var currentSince = since
        var serverTime: Date?
        var hasMore = true
        
        // Keep fetching while hasMore is true (pagination)
        while hasMore {
            let response = try await remoteConversationSyncDataSource.syncConversations(
                since: currentSince,
                limit: limit
            )
            
            guard let data = response.data else {
                throw DiscussionSyncError.noData
            }
            
            // Parse server time (only once)
            if serverTime == nil, let serverTimeString = data.serverTime.isEmpty ? nil : data.serverTime,
               let parsedServerTime = ISO8601DateFormatter().date(from: serverTimeString) {
                serverTime = parsedServerTime
            }
            
            // Échecs de la page courante. Remis à zéro à chaque page : une
            // page entièrement appliquée doit pouvoir avancer le curseur même
            // si une page antérieure a échoué — ce cas ne se produit pas
            // aujourd'hui puisqu'un échec interrompt, mais l'invariant reste
            // vrai si la boucle change.
            var failures: [(String, Error)] = []

            // Bloc 8, §16 et P0-4 — la page s'applique **atomiquement**, et le
            // curseur ne franchit qu'une page entièrement écrite.
            //
            // Une vraie transaction depuis B51 : soit la page entière est
            // écrite, soit rien ne l'est (une erreur annule tout), et les autres
            // tâches ne voient pas une page à moitié appliquée. Un rejeu reste
            // sûr : chaque écriture est un upsert par identité de conversation.
            do {
            try await database.withTransaction {
            // Process conversations in this batch
            for changedConv in data.changedConversations {
                do {
                    // Collect conversation ID for Phase 2
                    allConversationIds.append(changedConv.conversationId)
                    
                    // Does this conversation already exist here, under any of
                    // the identities it can be stored under? Matching on the
                    // primary key alone is what put two rows in the inbox for
                    // one person: a chat started on this device is stored under
                    // a local id and carries the server's id in `serverId`, so
                    // the server's own id never matched anything.
                    if let existingConv = try await existingConversation(for: changedConv) {
                        try await handleUpdatedConversation(changedConv, existing: existingConv)
                        totalUpdated += 1
                    } else {
                        try await handleCreatedConversation(changedConv)
                        totalCreated += 1
                    }
                } catch {
                    // Bloc 8, P0-5/P0-6 — l'échec est **retenu**, pas avalé.
                    //
                    // La version précédente écrivait un `print` et continuait la
                    // boucle ; le curseur avançait ensuite quand même. La
                    // conversation non écrite était donc franchie
                    // définitivement : la synchronisation suivante repartait
                    // après elle. Perte silencieuse en fonctionnement normal,
                    // pas seulement au crash.
                    failures.append((changedConv.conversationId, error))
                }
            }

            // Lever dans la transaction : c'est ce qui l'annule, et ce qui fait
            // rejouer la page au lieu de franchir la conversation non écrite.
            if let first = failures.first {
                throw DiscussionSyncError.pageNotFullyApplied(
                    failedConversationID: first.0,
                    failedCount: failures.count,
                    underlying: first.1
                )
            }
            }
            } catch {
                // §39 — l'échec laisse une trace, y compris en RELEASE où les
                // `print` d'origine disparaissaient.
                await telemetry.emit(
                    .syncFailed(stream: Self.conversationsStream,
                                code: SyncError.malformedPayload(reason: "apply").telemetryCode)
                )
                throw error
            }
            
            // Check if there are more pages
            hasMore = response.hasMore ?? false
            
            // §16 — le curseur ne franchit que des données réellement écrites.
            //
            // Une page partiellement appliquée n'avance pas le curseur : mieux
            // vaut re-télécharger la page au prochain passage (les écritures
            // sont idempotentes par `conversationId`) que sauter à jamais
            // l'élément perdu.
            if let nextCursor = data.nextSinceCursor {
                syncCursorStore.saveConversationsCursor(nextCursor)
                if hasMore {
                    // B53 — le serveur rend un jeton opaque (`<ms>|sync|AFTER` en
                    // base64), pas une date, et la requête ne sait envoyer que
                    // `since=`. Une position illisible n'est pas « depuis le
                    // début » : repartir de nil redemanderait la page 1 sans fin.
                    // On s'arrête ; la page suivante attend le contrat (cursor=).
                    if let next = ISO8601Timestamp.date(from: nextCursor) {
                        currentSince = next
                    } else {
                        debugLog("next page cursor is not a date — paging stops (B53)", category: "sync")
                        hasMore = false
                    }
                } else {
                    hasMore = false
                }
            } else {
                hasMore = false
            }
        }
        
        return ConversationSyncResult(
            createdCount: totalCreated,
            updatedCount: totalUpdated,
            serverTime: serverTime,
            nextCursor: nil, // Already saved in store
            hasMore: false,  // We fetched all pages
            conversationIds: allConversationIds // For Phase 2 message sync
        )
    }
    
    // MARK: - Private Sync Helpers

    /// The locally stored row this server conversation belongs to, if any.
    ///
    /// Three identities have to be tried, because a conversation can be stored
    /// under any of them:
    /// 1. the server id as primary key — a conversation this device learned
    ///    about from the server;
    /// 2. `server_id` — a conversation started here, linked on ACK;
    /// 3. the peer — a conversation started here whose ACK never carried
    ///    `oldConversationId`, so nothing ever linked it.
    ///
    /// Only (3) needs the peer, and only for direct conversations: a group is
    /// keyed by its group id and a broadcast channel by its conversation id, so
    /// neither can be ambiguous — and neither carries a peer to look up.
    private func existingConversation(
        for dto: ChangedConversationDTO
    ) async throws -> ConversationModel? {
        // Each lookup is followed through `mergedIntoId`: a duplicate that was
        // merged away is still listed by the server and still arrives here, and
        // updating the shell rather than the surviving thread would put this
        // conversation's activity somewhere the inbox does not look.
        if let byId = try? await database.fetchOne(
            ConversationModel.self,
            id: dto.conversationId
        ) {
            return await ConversationAliasResolver.resolved(byId, in: database)
        }

        let byServerId = QuerySpec(
            filter: FilterSpec("server_id == %@", .string(dto.conversationId)),
            limit: 1
        )
        if let linked = try? await database.fetch(ConversationModel.self, query: byServerId).first {
            return await ConversationAliasResolver.resolved(linked, in: database)
        }

        guard ConversationTypeMapper.isDirect(dto.conversationType), let peer = dto.peer else { return nil }
        return await DirectConversationLookup.unlinked(
            peerUserId: peer.userId,
            phone: peer.phone,
            in: database
        )
    }

    private func handleCreatedConversation(_ dto: ChangedConversationDTO) async throws {
        let conversationType = ConversationTypeMapper.model(from: dto.conversationType)
        let groupId = conversationType == .group ? dto.conversationId : nil
        
        // Parse lastActivityAt
        // Le backend envoie des fractions de seconde (`…T10:51:00.123Z`), que
        // l'`ISO8601DateFormatter` par défaut refuse : le repli sur `Date()`
        // datait alors chaque conversation de l'heure de la synchronisation (B52).
        let lastActivityAt = ISO8601Timestamp.date(from: dto.lastActivityAt) ?? Date()
        
        // Prepare last message fields if message exists
        var lastMessageText: String? = nil
        var lastMessageType: MessageTypeModel? = nil
        var lastMessageSenderName: String? = nil
        
        if let lastMessageDTO = dto.messages {
            lastMessageText = nil  // Will be set after message is saved
            lastMessageType = MessageModelMapper.mapInboundType(lastMessageDTO.typeMessage)
            lastMessageSenderName = fieldCrypto.encrypt(lastMessageDTO.senderName)
        }
        
        // 1. Create ConversationModel FIRST (before any messages/participants)
        var conversation = ConversationModel(
            id: dto.conversationId,
            serverId: dto.conversationId,
            groupId: groupId,
            type: conversationType,
            title: PeerDisplayName.sanitizedOrNil(
                dto.displayTitle,
                identifiers: [dto.conversationId, dto.peer?.userId ?? ""]
            ),
            avatarURL: dto.displayAvatar,
            lastMessageText: lastMessageText,
            lastMessageType: lastMessageType,
            lastMessageSenderName: lastMessageSenderName,
            lastMessageAt: lastActivityAt,
            unreadCount: dto.userState.unreadCount ?? 0,
            isPinned: dto.userState.pinned ?? false,
            isArchived: dto.userState.archived ?? false,
            createdAt: lastActivityAt,
            updatedAt: Date()
        )
        
        // ✅ SAVE CONVERSATION FIRST (satisfies foreign key constraint)
        try await database.save(conversation)
        
        // 2. Create peer participant for DIRECT conversations (now conversation exists)
        if conversationType == .direct, let peer = dto.peer {
            try await createPeerParticipant(
                peer: peer,
                conversationId: dto.conversationId
            )
        }
        
        // 3. Insert last message if exists and update conversation with preview
        if let lastMessageDTO = dto.messages,
           let messageModel = MessageModelMapper.toModel(
               from: lastMessageDTO,
               fieldCrypto: fieldCrypto
           ) {
            var message = messageModel
            message.conversationId = dto.conversationId
            try await database.save(message)
            
            // Now update conversation with last message preview text
            conversation.lastMessageText = fieldCrypto.encryptOptional(MessageModelMapper.buildLastMessagePreview(
                MessageModelMapper.toDomain(message, fieldCrypto: fieldCrypto)
            ))
            try await database.save(conversation)
        }
    }
    
    /// Applies a server conversation onto the row that already represents it.
    ///
    /// `existing.id` is the local identity and every child row keys off it —
    /// which is not always `dto.conversationId`. Writing participants and
    /// messages under the server id instead would orphan them from the thread
    /// they belong to, and leave the thread looking empty.
    private func handleUpdatedConversation(
        _ dto: ChangedConversationDTO,
        existing: ConversationModel
    ) async throws {
        var existingConv = existing
        let localId = existingConv.id
        // Read before anything below touches it — the forward-only guards on
        // `lastMessageAt`/the preview fields compare against what this row
        // already claimed, not against whatever this same sync is about to
        // write into it.
        let previousLastMessageAt = existingConv.lastMessageAt

        // Parse lastActivityAt
        // Le backend envoie des fractions de seconde (`…T10:51:00.123Z`), que
        // l'`ISO8601DateFormatter` par défaut refuse : le repli sur `Date()`
        // datait alors chaque conversation de l'heure de la synchronisation (B52).
        let lastActivityAt = ISO8601Timestamp.date(from: dto.lastActivityAt) ?? Date()

        // Update metadata
        // Sanitized: `displayTitle` carries the peer's account id whenever the
        // server has no name for them, and the inbox falls back to this title.
        let incomingTitle = PeerDisplayName.sanitized(
            dto.displayTitle,
            identifiers: [dto.conversationId, dto.peer?.userId ?? ""]
        )
        existingConv.title = incomingTitle.isEmpty ? existingConv.title : incomingTitle
        existingConv.avatarURL = dto.displayAvatar ?? existingConv.avatarURL
        // Never overwritten: the row we are updating may be the survivor of a
        // merge, reached by following the alias this sync actually named. Its
        // own server id is the one the outbound path publishes to.
        if existingConv.serverId == nil { existingConv.serverId = dto.conversationId }
        
        // Update last activity — forward only. A resync can report activity
        // older than what real-time sync already caught this device up to (a
        // paginated or stale batch, or a channel this device just posted to
        // itself), and letting it step backward reorders the inbox and rolls
        // the preview back to a message the user has already moved past.
        if previousLastMessageAt == nil || lastActivityAt >= previousLastMessageAt! {
            existingConv.lastMessageAt = lastActivityAt
        }

        // Increment unread count using YOUR logic
        let serverUnread = dto.userState.unreadCount ?? 0
        if serverUnread > existingConv.unreadCount {
            existingConv.unreadCount += (serverUnread - existingConv.unreadCount)
        }
        
        // Update user state
        existingConv.isPinned = dto.userState.pinned ?? existingConv.isPinned
        existingConv.isArchived = dto.userState.archived ?? existingConv.isArchived

        // Heal a broadcast that was stored as something else. Rows written before
        // `saveDiscussion` learned about channels were retyped `.group` by the
        // first post, which hid them from the channel list *and* from the chats
        // list. The server is the authority on what a conversation is, so when it
        // says BROADCAST, believe it. Deliberately one-way: nothing here retypes
        // a group or a direct chat, whose stored identity is settled locally.
        if ConversationTypeMapper.model(from: dto.conversationType) == .channel,
           existingConv.type != .channel {
            existingConv.type = .channel
        }

        existingConv.updatedAt = Date()
        
        try await database.save(existingConv)
        
        // Update/create peer participant for DIRECT conversations
        if existingConv.type == .direct, let peer = dto.peer {
            try await createPeerParticipant(
                peer: peer,
                conversationId: localId
            )
        }
        
        // Update last message if provided
        if let lastMessageDTO = dto.messages,
           let messageModel = MessageModelMapper.toModel(
               from: lastMessageDTO,
               fieldCrypto: fieldCrypto
           ) {
            var message = messageModel
            message.conversationId = localId
            
            // Check if message already exists
            if let storedMessage = try? await database.fetchOne(
                MessageModel.self,
                id: message.id
            ) {
                // Update existing message
                message.deliveryStatus = storedMessage.deliveryStatus
                message.createdAt = storedMessage.createdAt
            }
            
            try await database.save(message)

            // Update conversation last message preview — same forward-only
            // guard as `lastMessageAt` above: this DTO's message can be older
            // than the one already reflected in the preview, and the message
            // row itself is still worth persisting either way.
            if previousLastMessageAt == nil || message.timestamp >= previousLastMessageAt! {
                existingConv.lastMessageText = fieldCrypto.encryptOptional(MessageModelMapper.buildLastMessagePreview(
                    MessageModelMapper.toDomain(message, fieldCrypto: fieldCrypto)
                ))
                existingConv.lastMessageSenderName = fieldCrypto.encrypt(lastMessageDTO.senderName)
                existingConv.lastMessageType = MessageModelMapper.mapInboundType(lastMessageDTO.typeMessage)
                try await database.save(existingConv)
            }
        }
    }
    
    private func createPeerParticipant(
        peer: PeerInfoDTO,
        conversationId: String
    ) async throws {
        let participantId = ChatDeterministicId.uuid(from: "\(conversationId)_\(peer.userId)")
        
        // Check if participant already exists
        if let _ = try? await database.fetchOne(
            ConversationParticipantModel.self,
            id: participantId
        ) {
            // Already exists, skip
            return
        }
        
        let participant = ConversationParticipantModel(
            id: participantId,
            conversationId: conversationId,
            userId: peer.userId,
            contactId: nil,
            phone: peer.phone ?? "",  // ✅ Provide default for optional phone
            role: .member,
            // `displayName` is non-optional on the wire, so the server fills it
            // with the peer's account id when it cannot resolve a name. Keeping
            // that id would put it straight on the inbox row. Encrypted like
            // every other stored name — the read side decrypts either way.
            displayName: fieldCrypto.encrypt(
                PeerDisplayName.sanitized(peer.displayName, identifiers: [peer.userId, conversationId])
            ),
            avatarURL: peer.avatarUrl,
            customColor: nil,
            joinedAt: Date(),
            addedByUserId: nil,
            leftAt: nil,
            removedByUserId: nil,
            leaveReason: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try await database.save(participant)
    }
    
    // MARK: - Phase 2: Message Sync
    
    func syncConversationMessages(conversationId: String, since: Date?, limit: Int) async throws -> Int {
        var totalMessagesSynced = 0
        
        // ✅ VERIFY CONVERSATION EXISTS FIRST
        guard let requested = try? await database.fetchOne(
            ConversationModel.self,
            id: conversationId
        ) else {
            debugLog("[Sync] Warning: Conversation \(conversationId) not found, skipping message sync")
            return 0
        }

        // Une conversation fusionnée (alias, `mergedIntoId`) se synchronise
        // encore sous son id serveur, mais ses messages vont à la survivante :
        // rangés sous l'alias, que rien n'affiche, ils disparaissaient du fil
        // (un message envoyé est revenu sous l'alias et a quitté la salle).
        // Le serveur et le curseur gardent l'id demandé.
        let storageConversationId = await ConversationAliasResolver.resolved(requested, in: database)?.id
            ?? conversationId
        
        // ✅ Load cursor if not provided
        var messageSince = since
        if messageSince == nil {
            // Curseur serveur à 6–9 décimales (`…T08:14:55.347195400Z`) : le
            // formateur par défaut le refusait, et la reprise partait de
            // l'horloge du téléphone au lieu de la position serveur (B53).
            if let lastCursor = syncCursorStore.getMessagesCursor(for: conversationId),
               let cursorDate = ISO8601Timestamp.date(from: lastCursor) {
                messageSince = cursorDate
                debugLog("[Sync] Messages: Resuming conversation \(conversationId) from cursor: \(lastCursor)")
            } else if let lastSyncDate = syncCursorStore.getMessagesLastSyncDate(for: conversationId) {
                messageSince = lastSyncDate
                debugLog("[Sync] Messages: Resuming conversation \(conversationId) from last sync: \(lastSyncDate)")
            }
        }
        
        let response = try await remoteConversationSyncDataSource.syncConversationMessages(
            conversationId: conversationId,
            since: messageSince,
            limit: limit
        )
        
        guard let data = response.data else {
            throw DiscussionSyncError.noData
        }
        
        // Process timeline items and extract messages
        for item in data.items {
            // Only process MESSAGE type timeline items
            guard item.type == "MESSAGE", let timelineMessage = item.message else {
                continue
            }
            
            // ✅ Handle SYSTEM messages as ChatActions (checkpoints)
            if timelineMessage.isMessageSystem == true,
               timelineMessage.typeMessage == "SYSTEM" {
                debugLog("[Sync] Converting SYSTEM message to ChatAction: \(timelineMessage.content)")
                try await handleSystemMessageAsChatAction(
                    timelineMessage: timelineMessage,
                    conversationId: storageConversationId
                )
                continue
            }
            
            // Convert TimelineMessageDTO to InboundMessageDTO
            let inboundMessage = mapTimelineMessageToInbound(
                timelineMessage: timelineMessage,
                conversationId: conversationId
            )
            
            // Convert to MessageModel using existing mapper
            if let messageModel = MessageModelMapper.toModel(
                from: inboundMessage,
                fieldCrypto: fieldCrypto
            ) {
                var message = messageModel
                message.conversationId = storageConversationId
                
                // Check if message already exists
                if let existing = try? await database.fetchOne(
                    MessageModel.self,
                    id: message.id
                ) {
                    // Update existing message
                    message.deliveryStatus = existing.deliveryStatus
                    message.createdAt = existing.createdAt
                }
                
                try await database.save(message)
                totalMessagesSynced += 1
            }
        }
        
        // ✅ Save cursor for this conversation
        if let timestamp = response.timestamp {
            syncCursorStore.saveMessagesCursor(timestamp, for: conversationId)
        }
        
        return totalMessagesSynced
    }
    
    // MARK: - Timeline Message Mapper
    
    private func mapTimelineMessageToInbound(
        timelineMessage: TimelineMessageDTO,
        conversationId: String
    ) -> InboundMessageDTO {
        // Convert sentAt ISO8601 string to timestamp
        let timestamp: Double? = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: timelineMessage.sentAt) {
                return date.timeIntervalSince1970
            }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: timelineMessage.sentAt)?.timeIntervalSince1970
        }()
        
        return InboundMessageDTO(
            senderId: timelineMessage.senderId,
            senderName: timelineMessage.senderName ?? "",
            senderPhone: timelineMessage.senderPhone,
            senderAvatar: timelineMessage.senderAvatar,
            receiverId: nil,  // Not present in timeline response
            groupId: nil,     // Will be inferred from conversationType
            conversationId: conversationId,
            codeMessage: timelineMessage.codeMessage,
            content: timelineMessage.content,
            reply: timelineMessage.reply,
            typeMessage: timelineMessage.typeMessage,
            status: timelineMessage.status,
            forwarded: timelineMessage.forwarded,
            viewOnce: timelineMessage.viewOnce,
            isMoney: timelineMessage.isMoney,
            transactionId: timelineMessage.transactionId,
            isMessageSystem: timelineMessage.isMessageSystem,
            tenantId: nil,
            country: nil,
            timestamp: timestamp
        )
    }
    
    // MARK: - System Message to ChatAction Converter
    
    /// Converts SYSTEM messages (like CONVERSATION_CREATED, CONTACT_BLOCKED, etc.)
    /// into ChatAction checkpoints so they display properly in the timeline
    private func handleSystemMessageAsChatAction(
        timelineMessage: TimelineMessageDTO,
        conversationId: String
    ) async throws {
        // The same reading as every other inbound path. Housekeeping
        // (CONVERSATION_CREATED) and unknown kinds are not stored.
        let actionType: ChatActionType
        switch ConversationSystemRecord.kind(content: timelineMessage.content) {
        case .action(let type):
            actionType = type
        case .conversationCreated:
            return
        case .unknown:
            debugLog("[Sync] Unknown SYSTEM message type: \(timelineMessage.content)")
            return
        }
        
        // Parse timestamp
        let timestamp: Date = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: timelineMessage.sentAt) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: timelineMessage.sentAt) ?? Date()
        }()
        
        // Create ChatActionItem
        let chatAction = ChatActionItem(
            id: timelineMessage.codeMessage,  // Use message ID as action ID
            conversationId: conversationId,
            actionType: actionType,
            performedBy: timelineMessage.senderId,
            targetId: nil,  // System messages don't have targets
            metadata: timelineMessage.senderName != nil ? ["performedByName": timelineMessage.senderName!] : nil,
            timestamp: timestamp
        )
        
        // Save to database
        try await chatActionsDataSource.saveChatAction(chatAction)
        debugLog("[Sync] Saved SYSTEM message as ChatAction: \(actionType.rawValue)")
    }
    
    // MARK: - Master Sync Orchestrator
    
    func performFullSync(limit: Int) async throws {
        // ✅ Record sync start
        SyncHealthMonitor.shared.recordSyncStart(topic: .conversations)
        
        // ✅ Load last sync cursor/date from storage
        var conversationsSince: Date? = nil
        if let lastCursor = syncCursorStore.getConversationsCursor(),
           let cursorDate = ISO8601DateFormatter().date(from: lastCursor) {
            conversationsSince = cursorDate
            debugLog("[Sync] Resuming from last cursor: \(lastCursor)")
        } else if let lastSyncDate = syncCursorStore.getConversationsLastSyncDate() {
            conversationsSince = lastSyncDate
            debugLog("[Sync] Resuming from last sync date: \(lastSyncDate)")
        } else {
            debugLog("[Sync] No previous sync found, starting from beginning")
        }
        
        var conversationsHasMore = true
        var totalConversationsSynced = 0
        
        debugLog("[Sync] Starting full synchronization...")
        
        // Keep alternating between Phase 1 and Phase 2 until no more conversations
        while conversationsHasMore {
            // PHASE 1: Fetch batch of conversations
            debugLog("[Sync] Phase 1: Fetching conversations (since: \(conversationsSince?.description ?? "nil"))...")
            let convResult = try await syncConversations(since: conversationsSince, limit: limit)
            
            totalConversationsSynced += convResult.createdCount + convResult.updatedCount
            
            debugLog("[Sync] Phase 1 complete: \(convResult.createdCount) created, \(convResult.updatedCount) updated, \(convResult.conversationIds.count) total IDs")
            
            // PHASE 2: Sync messages for all conversations in this batch
            if !convResult.conversationIds.isEmpty {
                debugLog("[Sync] Phase 2: Syncing messages for \(convResult.conversationIds.count) conversations...")
                
                for (index, conversationId) in convResult.conversationIds.enumerated() {
                    do {
                        let messageCount = try await syncConversationMessages(
                            conversationId: conversationId,
                            since: nil, // TODO: Track per-conversation last sync time
                            limit: limit
                        )
                        debugLog("[Sync] Phase 2: [\(index + 1)/\(convResult.conversationIds.count)] Conversation \(conversationId) - \(messageCount) messages synced")
                    } catch {
                        debugLog("[Sync] Phase 2: Failed to sync messages for \(conversationId): \(error)")
                        // Continue with other conversations
                    }
                }
                
                debugLog("[Sync] Phase 2 complete for batch")
            }
            
            // Check if we need to fetch more conversations
            conversationsHasMore = convResult.hasMore
            
            if conversationsHasMore {
                // Update cursor for next conversation fetch
                if let serverTime = convResult.serverTime {
                    conversationsSince = serverTime
                    debugLog("[Sync] More conversations available, will fetch next batch...")
                } else {
                    // No server time, stop to avoid infinite loop
                    debugLog("[Sync] Warning: hasMore=true but no serverTime, stopping")
                    conversationsHasMore = false
                }
            } else {
                debugLog("[Sync] No more conversations to fetch")
            }
        }
        
        // ✅ Record successful sync
        SyncHealthMonitor.shared.recordSyncSuccess(topic: .conversations, itemsSynced: totalConversationsSynced)
        
        debugLog("[Sync] Full synchronization complete!")
    }
}


// MARK: - Sync Error

/// Renommé au Bloc 8 : `SyncError` désigne désormais la taxonomie publique de
/// CoreKit (`SyncErrors.swift`). Un type local du même nom l'occultait dans
/// tout `FeatureChat` — le module qui doit précisément l'adopter — et aurait
/// obligé à écrire `CoreKit.SyncError` partout ailleurs.
enum DiscussionSyncError: Error {
    case noData

    /// Une page n'a pas été appliquée en entier — le curseur n'a pas avancé.
    ///
    /// Bloc 8, P0-5. Distingué de `noData` parce que la reprise diffère : ici
    /// la page est re-téléchargeable telle quelle, et la relancer est le
    /// comportement correct.
    case pageNotFullyApplied(
        failedConversationID: String,
        failedCount: Int,
        underlying: Error
    )
}
