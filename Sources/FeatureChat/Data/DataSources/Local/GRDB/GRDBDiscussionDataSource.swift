//
//  GRDBDiscussionDataSource.swift
//  FeatureChat
//
//  Adapted to new model schema:
//  – ConversationModel replaces DiscussionModel
//  – MessageModel uses String ids, embedded content, deliveryStatus
//  – ContactModel uses new non-optional fields
//

import Foundation
import WaanguCoreKit

final class GRDBDiscussionDataSource: LocalDiscussionDataSourceProtocol {

    private let store: any DatabaseRepositoryProtocol
    private let fieldCrypto: any FieldEncryptionServiceProtocol
    private let preferenceDataSource: LocalChatPreferenceDataSourceProtocol

    init(
        store: any DatabaseRepositoryProtocol,
        fieldCrypto: any FieldEncryptionServiceProtocol,
        preferenceDataSource: LocalChatPreferenceDataSourceProtocol
    ) {
        self.store = store
        self.fieldCrypto = fieldCrypto
        self.preferenceDataSource = preferenceDataSource
    }

    // MARK: - Fetch discussions list

    func fetchDiscussions() async throws -> [DiscussionChatItem] {
        let query = QuerySpec(
            filter: FilterSpec("is_archived == %@", .bool(false)),
            sort: [SortSpec("last_message_at", ascending: false)]
        )
        let allConversations = try await store.fetch(ConversationModel.self, query: query)

        // Exclude group conversations that are still pending or failed (managed via pendingGroups separately)
        let conversations = allConversations.filter { conv in
            // A row already merged into another is not a conversation any more,
            // it is a forwarding address. Skipping it here is the whole point of
            // merging: the work was done once and written down, and the fetch
            // just honours it.
            guard conv.mergedIntoId == nil else { return false }
            guard conv.type == .group else { return true }
            let meta = (conv.assignedAgentName ?? "").components(separatedBy: "|")
            let isPending = meta.count > 1 ? meta[1] == "1" : false
            let syncStatus = meta.first ?? ""
            // Only show a group conversation when it's been synced (not pending/failed)
            return !isPending && syncStatus == GroupSyncStatus.synced.rawValue
        }

        var rows: [DiscussionDeduplicator.Row] = []

        for conversation in conversations {
            let item = try await buildDiscussionItem(from: conversation)
            rows.append(DiscussionDeduplicator.Row(conversation: conversation, item: item))
        }

        // One row per person, whatever the table holds. The stored rows are
        // merged separately and cannot always be — a conversation the server
        // still lists returns on the next sync — so the inbox collapses what it
        // reads rather than trusting the table to be clean.
        return DiscussionDeduplicator.collapsed(rows)
    }

    // MARK: - Save discussion

    func saveDiscussion(_ discussion: DiscussionChatItem) async throws {
        // Upsert conversation record
        let conversationId = discussion.conversationId
        let isGroup = discussion.contact?.isGroup ?? false
debugLog("this will be called for saving discussion \(discussion.conversationId)")
        let existingConversation = try await fetchConversation(id: conversationId)
        debugLog(
            "SAVE_DISCUSSION asked=\(conversationId) foundExistingRow=\(existingConversation != nil) "
            + "carryingDraft=\(existingConversation?.draft.map { "\"\($0.prefix(20))\"" } ?? "nil") "
            + "carryingIsShowing=\(existingConversation?.isShowingDraft.map(String.init) ?? "nil")",
            category: "chat-draft"
        )
        let lastMsgText = MessageModelMapper.buildLastMessagePreview(discussion.lastMessage)

        // An empty `codeMessage` is a placeholder — a row written just to
        // satisfy the conversation foreign key before any post exists (see
        // `ChannelLocalConversationSync`), not a real message. On a row that
        // already exists, a placeholder must never step on the last message
        // it already has: persisting a channel a second time is not the same
        // event as a message actually arriving in it.
        let hasRealMessage = !discussion.lastMessage.codeMessage.isEmpty
        let keepsLastMessage = existingConversation != nil && !hasRealMessage

        // A group conversation already exists before anything can be written into
        // it — you cannot be called in a group you are not already in, nor message
        // one. So a stored group's identity is settled, and this write only moves
        // the last message forward. Callers that describe the *other party* rather
        // than the thread — the call history, which passes the peer it dialled with
        // `isGroup: false` — would otherwise retype the group as a direct chat and
        // rename it after that peer.
        let existingIsGroup = existingConversation?.type == .group

        // A broadcast channel's identity is settled the same way a group's is —
        // Identity created it, this device only writes into it. Without this the
        // first post retyped the row `.group`, because that is what a broadcast
        // send looks like from here (`isGroup: true`, no peer). The row then had
        // no group sync metadata either, so the chats list skipped it *and* the
        // channel list stopped recognising it: persisted, and nowhere to be seen.
        let existingIsChannel = existingConversation?.type == .channel
        let incomingIsChannel = discussion.contact?.isChannel == true
        let keepsStoredIdentity = existingIsGroup || existingIsChannel

        // The kind comes with the write now — `ContactChannel.isChannel`, set
        // from `ConversationKind` at the top of the send path. The stored type
        // is still honoured as a second line: a row already known to be a
        // channel stays one even if an older writer says otherwise.
        let resolvedType: ConversationTypeModel
        if existingIsChannel || incomingIsChannel {
            resolvedType = .channel
        } else if existingIsGroup || isGroup {
            resolvedType = .group
        } else {
            resolvedType = .direct
        }

        let conversation = ConversationModel(
            id: existingConversation?.id ?? conversationId,
            serverId: existingConversation?.serverId,
            // Dropped entirely before this: every group write nulled the stored
            // group id and left `resolvedGroupId` to fall back to the server id.
            groupId: existingConversation?.groupId,
            type: resolvedType,
            title: keepsStoredIdentity
                ? existingConversation?.title
                : (isGroup ? discussion.contact?.userName : nil),
            avatarURL: keepsStoredIdentity
                ? existingConversation?.avatarURL
                : discussion.contact?.image,
            lastMessageText: keepsLastMessage ? existingConversation?.lastMessageText : fieldCrypto.encryptOptional(lastMsgText),
            lastMessageType: keepsLastMessage
                ? existingConversation?.lastMessageType
                : MessageModelMapper.mapType(discussion.lastMessage.typeMessage),
            lastMessageSenderName: keepsLastMessage
                ? existingConversation?.lastMessageSenderName
                : (discussion.lastMessage.senderName.isEmpty ? nil : discussion.lastMessage.senderName),
            lastMessageAt: keepsLastMessage ? existingConversation?.lastMessageAt : discussion.lastMessage.createdAt,
            unreadCount: existingConversation?.unreadCount ?? discussion.count,
            isPinned: existingConversation?.isPinned ?? false,
            isArchived: existingConversation?.isArchived ?? false,
            draft: existingConversation?.draft,
            isShowingDraft: existingConversation?.isShowingDraft,
            // Carried like `serverId` and `groupId`: this row is rebuilt from a
            // `DiscussionChatItem` on every save, and a merge alias dropped here
            // would resurrect a duplicate the next time the inbox is read.
            mergedIntoId: existingConversation?.mergedIntoId,
            // ✅ CRITICAL: preserve the group sync metadata packed in assignedAgentName.
            // GroupMapper stores "syncStatus|isPending|retryCount|createdBy|color" here.
            // serverId is stored in ConversationModel.serverId.
            assignedAgentName: existingConversation?.assignedAgentName,
            createdAt: existingConversation?.createdAt ?? Date(),
            updatedAt: Date()
        )
        try await store.save(conversation)

        // Save the contact if direct chat — only on first message (avoid duplicate contacts)
        if !isGroup, !existingIsGroup, let contact = discussion.contact, !contact.userId.isEmpty {
            let contactId = contact.id.isEmpty
                ? deterministicId(from: contact.userId)
                : contact.id
            // Only insert if not already persisted for this userId
            let existingQuery = QuerySpec(
                filter: FilterSpec("user_id == %@", .string(contact.userId)),
                limit: 1
            )
            let existing = try await store.fetch(ContactModel.self, query: existingQuery)
            if existing.isEmpty {
                let contactModel = ContactModel(
                    id: contactId,
                    userId: contact.userId,
                    phone: contact.phone,
                    name: fieldCrypto.encrypt(contact.userName),
                    avatarURL: contact.image,
                    isRegistered: true,
                    isBlocked: contact.isBlocked
                )
                try await store.save(contactModel)
            }
        }

        // Direct chats must store a peer participant so fetchDiscussions can resolve phone/name.
        // Without this, the inbox falls back to an unrelated ContactModel and reuse-by-phone fails.
        // Never on a group: `buildDiscussionItem` reads the first participant that
        // is not you, so one peer row written here is enough to make the group
        // render as a one-to-one chat with whoever that peer is.
        if !isGroup, !existingIsGroup, let contact = discussion.contact, !contact.phone.isEmpty {
            try await upsertDirectPeerParticipant(
                conversationId: conversation.id,
                contact: contact
            )
        }

        // Save the message if it has content
        let msg = discussion.lastMessage
        if !msg.codeMessage.isEmpty {
            try await saveMessage(msg, conversationId: conversationId)
        }
    }

    /// Ensures one active peer row exists for a direct conversation.
    private func upsertDirectPeerParticipant(
        conversationId: String,
        contact: ContactChannel
    ) async throws {
        // The account id, and only the account id. Falling back to the phone
        // here filed a phone number under `user_id`, so the same person reached
        // by two routes ended up with two different identities and the inbox
        // could never tell that the two conversations were one.
        let peerUserId = contact.userId
        // Rows are still keyed by whatever identifies the peer, since a peer we
        // only know by number has no account id to key on.
        let participantKey = peerUserId.isEmpty ? contact.phone : peerUserId
        guard !participantKey.isEmpty else { return }
        let existingQuery = QuerySpec(
            filter: FilterSpec(
                "conversation_id == %@ AND user_id == %@",
                .string(conversationId),
                .string(participantKey)
            ),
            limit: 1
        )
        let existing = try await store.fetch(ConversationParticipantModel.self, query: existingQuery)
        if let current = existing.first {
            // Keep phone/name fresh if they changed, but don't duplicate the row.
            let updated = ConversationParticipantModel(
                id: current.id,
                conversationId: current.conversationId,
                userId: current.userId,
                contactId: current.contactId ?? (contact.id.isEmpty ? nil : contact.id),
                phone: contact.phone,
                role: current.role,
                displayName: PeerDisplayName.sanitized(
                    contact.userName,
                    identifiers: [contact.userId, contact.id]
                ).isEmpty
                    ? current.displayName
                    : fieldCrypto.encrypt(contact.userName),
                avatarURL: contact.image ?? current.avatarURL,
                customColor: current.customColor,
                joinedAt: current.joinedAt,
                addedByUserId: current.addedByUserId,
                leftAt: current.leftAt,
                removedByUserId: current.removedByUserId,
                leaveReason: current.leaveReason,
                createdAt: current.createdAt,
                updatedAt: Date()
            )
            try await store.save(updated)
            return
        }

        let contactId = contact.id.isEmpty
            ? deterministicId(from: participantKey)
            : contact.id
        let participant = ConversationParticipantModel(
            id: deterministicId(from: "\(conversationId)_\(participantKey)"),
            conversationId: conversationId,
            userId: peerUserId,
            contactId: contactId,
            phone: contact.phone,
            role: .member,
            // The number is not a name. Storing it here made every nameless peer
            // look named, so the read side could never tell the two apart and
            // fall back to the number deliberately.
            displayName: fieldCrypto.encrypt(
                PeerDisplayName.sanitized(contact.userName, identifiers: [contact.userId, contact.id])
            ),
            avatarURL: contact.image,
            joinedAt: Date(),
            leftAt: nil
        )
        try await store.save(participant)
    }

    // MARK: - Update discussion setting

    func updateDiscussionSetting(_ discussion: DiscussionChatItem) async throws {
        guard let existing = try await fetchConversation(id: discussion.conversationId) else {
            return
        }

        guard let setting = discussion.setting else { return }

        // 1. Update pin/archive on ConversationModel
        let updated = DiscussionSettingMapper.apply(setting, to: existing)
        try await store.save(updated)

        // 2. Persist rich preferences (mute, ephemeral, lock…) to ChatPreferenceModel
        try await preferenceDataSource.savePreference(setting, conversationId: discussion.conversationId)
    }

    // MARK: - Fetch messages for conversation

    func fetchMessages(_ conversationId: String) async throws -> [MessageDataItem] {
        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversationId)),
            sort: [SortSpec("timestamp", ascending: true)]
        )
        let models = try await store.fetch(MessageModel.self, query: query)
        return MessageTimelineVisibility.filterVisible(models)
            .map { MessageModelMapper.toDomain($0, fieldCrypto: fieldCrypto) }
    }

    func fetchMessagesWithPagination(
        conversationId: String,
        before cursor: Date?,
        pageSize: Int
    ) async throws -> [MessageDataItem] {
        // Over-fetch then filter in memory — `isDeletedForAll` is not an indexed SQL column.
        let fetchLimit = max(pageSize * 4, pageSize)
        let query: QuerySpec
        if let cursor {
            query = QuerySpec(
                filter: FilterSpec(
                    "conversation_id == %@ AND timestamp < %@",
                    .string(conversationId),
                    .date(cursor)
                ),
                sort: [SortSpec("timestamp", ascending: false)],
                limit: fetchLimit
            )
        } else {
            query = QuerySpec(
                filter: FilterSpec("conversation_id == %@", .string(conversationId)),
                sort: [SortSpec("timestamp", ascending: false)],
                limit: fetchLimit
            )
        }
        let models = try await store.fetch(MessageModel.self, query: query)
        let visible = Array(MessageTimelineVisibility.filterVisible(models).prefix(pageSize))
        return visible.reversed().map { MessageModelMapper.toDomain($0, fieldCrypto: fieldCrypto) }
    }

    // MARK: - Delete

    func deleteDiscussion(conversationId: String) async throws {
        // Delete all messages in conversation
        try await store.deleteAll(
            MessageModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string(conversationId)))
        )
        // Delete participants
        try await store.deleteAll(
            ConversationParticipantModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string(conversationId)))
        )
        // Delete the conversation itself
        if let existing = try await fetchConversation(id: conversationId) {
            try await store.delete(ConversationModel.self, id: existing.id)
        }
    }

    func deleteAllDiscussionMessages(conversationId: String) async throws {
        try await store.deleteAll(
            MessageModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string(conversationId)))
        )
        // Reset last message fields on conversation
        if let existing = try await fetchConversation(id: conversationId) {
            let updated = ConversationModel(
                id: existing.id,
                serverId: existing.serverId,
                type: existing.type,
                title: existing.title,
                avatarURL: existing.avatarURL,
                lastMessageText: nil,
                lastMessageType: nil,
                lastMessageSenderName: nil,
                lastMessageAt: nil,
                unreadCount: 0,
                isPinned: existing.isPinned,
                isArchived: existing.isArchived,
                draft: existing.draft,
                isShowingDraft: existing.isShowingDraft,
                assignedAgentName: existing.assignedAgentName,
                lastReadMessageId: existing.lastReadMessageId,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
            try await store.save(updated)
        }
    }

    func deleteAllDiscussions() async throws {
        try await store.deleteAll(MessageModel.self, query: nil)
        try await store.deleteAll(ConversationParticipantModel.self, query: nil)
        try await store.deleteAll(ConversationModel.self, query: nil)
    }

    func clearUnreadCount(conversationId: String) async throws {
        guard var conversation = try await resolveConversation(conversationId: conversationId) else {
            return
        }
        guard conversation.unreadCount != 0 else { return }
        conversation.unreadCount = 0
        conversation.updatedAt = Date()
        try await store.save(conversation)
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }

    /// Writes the draft straight onto the conversation row rather than through
    /// `saveDiscussion`, which rebuilds the whole row from a `DiscussionChatItem`
    /// and would flatten the last-message fields on the way past.
    ///
    /// No `lastMessageAt` bump: a draft is not activity, and moving the row to
    /// the top of the list because someone half-typed a word is not what the
    /// list's ordering means.
    func saveDraft(conversationId: String, text: String) async throws {
        guard var conversation = try await resolveConversation(conversationId: conversationId) else {
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = trimmed.isEmpty ? nil : text
        let isShowingDraft = draft != nil

        guard conversation.draft != draft
                || conversation.isShowingDraft != isShowingDraft else { return }

        conversation.draft = draft
        conversation.isShowingDraft = isShowingDraft
        conversation.updatedAt = Date()
        try await store.save(conversation)
        debugLog(
            "WRITE asked=\(conversationId) row=\(conversation.id) serverId=\(conversation.serverId ?? "nil") "
            + "draft=\(draft.map { "\"\($0.prefix(20))\"" } ?? "nil") isShowing=\(isShowingDraft)",
            category: "chat-draft"
        )
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }

    func fetchDraft(conversationId: String) async throws -> String? {
        guard let conversation = try await resolveConversation(conversationId: conversationId) else {
            return nil
        }
        return conversation.isShowingDraft == true ? conversation.draft : nil
    }

    func outboundConversationId(for localConversationId: String) async -> String {
        guard !localConversationId.isEmpty,
              let conversation = try? await resolveConversation(conversationId: localConversationId) else {
            return localConversationId
        }
        return conversation.resolvedServerId
    }

    /// The id a multi-party message travels under.
    ///
    /// Channels count: a broadcast is fanned out to participants exactly like a
    /// group, and the published message carries the id either way. Excluding
    /// them here left the *stored* copy of a channel post without one while the
    /// published copy had it — the same message, described two ways.
    func outboundGroupId(for localConversationId: String) async -> String? {
        guard !localConversationId.isEmpty,
              let conversation = try? await resolveConversation(conversationId: localConversationId),
              conversation.type.isMultiParty
        else { return nil }
        return conversation.resolvedGroupId
    }

    // MARK: - Private: Build DiscussionChatItem from ConversationModel

    private func buildDiscussionItem(from conversation: ConversationModel) async throws -> DiscussionChatItem {
        if conversation.type == .copilot { return try await copilotItem(from: conversation) }
        // A broadcast channel has no peer either, so it resolves the same way a
        // group does: title and avatar come off the conversation row.
        let isChannel = conversation.type == .channel
        // **Salle, et pas seulement « sans pair ».** Élargir cette condition à
        // tout ce qui n'a pas d'interlocuteur (`!hasPeer`) y faisait entrer les
        // conversations `support` : elles basculaient sur la branche du titre,
        // qui lit `conversation.title` **sans le déchiffrer**, et l'inbox
        // affichait le chiffré en clair à la place du nom du correspondant.
        let isGroup = conversation.type.isMultiParty

        // Resolve contact channel
        let contactChannel: ContactChannel
        if isGroup {
            contactChannel = ContactChannel(
                userName: conversation.title ?? (isChannel ? "Channel" : "Group"),
                phone: "",
                image: conversation.avatarURL,
                isBlocked: false,
                isGroup: true,
                isChannel: isChannel,
                id: conversation.id
            )
        } else {
            // Find the participant that is NOT the current user
            let participantQuery = QuerySpec(
                filter: FilterSpec(
                    "conversation_id == %@ AND user_id != %@",
                    .string(conversation.id),
                    .string(CurrentSessionInfo.shared.currentUid)
                ),
                limit: 1
            )
            let participants = try await store.fetch(ConversationParticipantModel.self, query: participantQuery)

            if let participant = participants.first {
                let identifiers = [participant.userId, participant.contactId ?? "", conversation.id]
                var name = PeerDisplayName.sanitized(
                    fieldCrypto.decrypt(participant.displayName),
                    identifiers: identifiers
                )
                var phone = participant.phone
                var avatar = participant.avatarURL
                var isBlocked = false

                // The address book fills what the participant row lacks. Only
                // consulted when something is missing: the common path already
                // has both, and this runs once per row in the inbox.
                if name.isEmpty || phone.isEmpty,
                   let stored = try await contact(forUserId: participant.userId) {
                    if name.isEmpty {
                        name = PeerDisplayName.sanitized(
                            fieldCrypto.decrypt(stored.name),
                            identifiers: identifiers
                        )
                    }
                    if phone.isEmpty { phone = stored.phone }
                    if avatar == nil { avatar = stored.avatarURL }
                    isBlocked = stored.isBlocked
                }

                contactChannel = ContactChannel(
                    userName: name,
                    phone: phone,
                    image: avatar,
                    isBlocked: isBlocked,
                    isGroup: false,
                    id: participant.contactId ?? participant.userId,
                    userId: participant.userId
                )
            } else {
                // No peer row — all we have is whatever the conversation itself
                // remembers. A contact is accepted only when the conversation
                // actually names it: this used to fall back to `contacts.first`,
                // which put an arbitrary person's name and number on a thread
                // that had nothing to do with them.
                let title = conversation.title ?? ""
                let contactQuery = QuerySpec(
                    filter: FilterSpec(
                        "user_id != %@ AND is_registered == %@",
                        .string(CurrentSessionInfo.shared.currentUid),
                        .bool(true)
                    ),
                    limit: 50
                )
                let contacts = try await store.fetch(ContactModel.self, query: contactQuery)
                let matched = contacts.first { candidate in
                    (!candidate.phone.isEmpty && title.contains(candidate.phone))
                    || (!candidate.userId.isEmpty && title.contains(candidate.userId))
                }

                if let contact = matched {
                    contactChannel = ContactChannel(
                        userName: PeerDisplayName.sanitized(
                            fieldCrypto.decrypt(contact.name),
                            identifiers: [contact.userId, contact.id, conversation.id]
                        ),
                        phone: contact.phone,
                        image: contact.avatarURL,
                        isBlocked: contact.isBlocked,
                        isGroup: false,
                        id: contact.id,
                        userId: contact.userId
                    )
                } else {
                    contactChannel = ContactChannel(
                        userName: PeerDisplayName.sanitized(
                            title,
                            identifiers: [conversation.id, conversation.serverId ?? ""]
                        ),
                        phone: "",
                        image: nil,
                        isBlocked: false,
                        isGroup: false,
                        id: conversation.id
                    )
                }
            }
        }

        // Load last message: skip delete-for-me; keep delete-for-everyone.
        // If none remain, keep the discussion with an empty placeholder.
        let lastMessageQuery = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversation.id)),
            sort: [SortSpec("timestamp", ascending: false)]
        )
        let lastMessages = try await store.fetch(MessageModel.self, query: lastMessageQuery)
        let messageItem: MessageDataItem
        if let lastMessage = MessageTimelineVisibility.newestVisible(in: lastMessages) {
            var item = MessageModelMapper.toDomain(lastMessage, fieldCrypto: fieldCrypto)
            // Denormalized preview is rebuilt on every edit/delete — prefer it for list subtitle.
            if lastMessage.type == .text,
               let preview = conversation.lastMessageText.map({ fieldCrypto.decrypt($0) })?.trimmingCharacters(in: .whitespacesAndNewlines),
               !preview.isEmpty {
                item.message.text = preview
            }
            messageItem = item
        } else {
            messageItem = MessageDataItem(
                codeMessage: "",
                senderId: "",
                groupId: conversation.id,
                typeMessage: .TEXT,
                message: MessageContent(text: ""),
                status: .PENDING,
                createdAt: conversation.lastMessageAt ?? conversation.createdAt
            )
        }

        debugLog(
            "READ row=\(conversation.id) serverId=\(conversation.serverId ?? "nil") "
            + "draft=\(conversation.draft.map { "\"\($0.prefix(20))\"" } ?? "nil") "
            + "isShowing=\(conversation.isShowingDraft.map(String.init) ?? "nil")",
            category: "chat-draft"
        )
        return DiscussionChatItem(
            lastMessage: messageItem,
            conversationId: conversation.id,
            contact: contactChannel,
            count: conversation.unreadCount,
            setting: try await loadMergedSetting(conversation: conversation),
            draft: conversation.isShowingDraft == true ? conversation.draft : nil
        )
    }

    /// La conversation Waangu Copilot : pas de correspondant à résoudre, pas de
    /// message de messagerie — son aperçu est celui que Copilot a écrit.
    private func copilotItem(from conversation: ConversationModel) async throws -> DiscussionChatItem {
        DiscussionChatItem(
            lastMessage: MessageDataItem(
                codeMessage: "",
                senderId: "",
                groupId: conversation.id,
                typeMessage: .TEXT,
                message: MessageContent(text: conversation.lastMessageText.map { fieldCrypto.decrypt($0) } ?? ""),
                status: .PENDING,
                createdAt: conversation.lastMessageAt ?? conversation.createdAt
            ),
            conversationId: conversation.id,
            contact: ContactChannel(userName: FinanceStrings.copilotName, phone: "", image: nil,
                                    isBlocked: false, isGroup: false, id: conversation.id, isCopilot: true),
            count: 0,
            setting: try await loadMergedSetting(conversation: conversation),
            draft: nil
        )
    }

    private func loadMergedSetting(conversation: ConversationModel) async throws -> UserConversationSetting? {
        // Fetch rich preference from ChatPreferenceModel (mute, ephemeral, etc.)
        // Errors are silenced — we fall back to just pin/archive from ConversationModel.
        let query = QuerySpec(
            filter: FilterSpec(
                "target_type == %@ AND target_key == %@",
                .string(PreferenceTargetTypeModel.conversation.rawValue),
                .string(conversation.id)
            ),
            limit: 1
        )
        let preference = try? await store.fetch(ChatPreferenceModel.self, query: query).first
        return DiscussionSettingMapper.mergedSetting(from: conversation, preference: preference)
    }

    // MARK: - Private: Save message

    private func saveMessage(_ message: MessageDataItem, conversationId: String) async throws {
        let model = MessageModelMapper.toModel(
            from: message,
            conversationId: conversationId,
            fieldCrypto: fieldCrypto
        )
        try await store.save(model)
    }

    /// Produces a stable lowercase String id from any arbitrary string using a simple hash.
    /// Keeps the same value deterministic across calls for non-UUID backend ids.
    private func deterministicId(from string: String) -> String {
        var hash = string.utf8.reduce(UInt64(14695981039346656037)) { acc, byte in
            (acc ^ UInt64(byte)) &* 16777619
        }
        // Build 16 bytes from the hash (repeat to fill)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i]     = UInt8((hash >> (i * 8)) & 0xFF)
            bytes[i + 8] = UInt8((hash >> (i * 8)) & 0xFF)
        }
        // Set UUID version 5 bits
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )).uuidString.lowercased()
    }

    // MARK: - Private: Fetch conversation

    private func fetchConversation(id: String) async throws -> ConversationModel? {
        try await store.fetchOne(ConversationModel.self, id: id)
    }

    /// The address-book row for a Waangu account, when we hold one.
    private func contact(forUserId userId: String) async throws -> ContactModel? {
        guard !userId.isEmpty else { return nil }
        let query = QuerySpec(
            filter: FilterSpec("user_id == %@", .string(userId)),
            limit: 1
        )
        return try await store.fetch(ContactModel.self, query: query).first
    }

    /// The conversation an id refers to — by local id, by server id, and
    /// through a merge alias.
    ///
    /// Every caller that reads or writes conversation state goes through here
    /// (unread, drafts, the outbound ids), so following the alias in one place
    /// is what keeps a merged-away duplicate from quietly collecting state that
    /// nothing renders.
    private func resolveConversation(conversationId: String) async throws -> ConversationModel? {
        var conversation = try await fetchConversation(id: conversationId)

        if conversation == nil {
            let query = QuerySpec(
                filter: FilterSpec("server_id == %@", .string(conversationId)),
                limit: 1
            )
            conversation = try await store.fetch(ConversationModel.self, query: query).first
        }

        return try await followingMergeAlias(conversation)
    }

    private func followingMergeAlias(
        _ conversation: ConversationModel?
    ) async throws -> ConversationModel? {
        await ConversationAliasResolver.resolved(conversation, in: store)
    }
}
