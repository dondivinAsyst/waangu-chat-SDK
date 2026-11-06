//
//  ConversationDeduplicationService.swift
//  FeatureChat
//
//  Folds conversation rows that are the same thread stored twice.
//

import Foundation
import WaanguCoreKit

/// Repairs inboxes that already hold two rows for one person.
///
/// Nothing in the schema keys a direct conversation by peer, and until the sync
/// path learned to match on `server_id` and on the peer, two writers could each
/// create a row for the same thread: the local send (a fresh UUID) and the
/// conversation sync (the server's id). Fixing the writers stops new pairs;
/// this fixes the pairs already on the device.
///
/// Every duplicate is merged, and the merge is written down — the work happens
/// once, not on every read. How the losing row ends depends on who owns it:
///
/// - a row the server has never named is **deleted**, its history moved first;
/// - a row carrying a `serverId` is **kept as an alias** (`mergedIntoId`), its
///   history moved just the same. Deleting that one buys nothing: the backend
///   still lists it, so the next sync writes it straight back and the merge
///   undoes itself on every launch. The shell stays behind to absorb that sync
///   and redirect it — `resolveConversation` follows the pointer, so unread,
///   drafts and inbound messages all land on the surviving thread.
///
/// Idempotent, and run after every sync rather than once per install — see
/// `runIfNeeded()`.
/// `@unchecked Sendable`: every stored property is set once at init and the
/// database it talks to serialises its own access. The conformance is what lets
/// the merge body run inside `withTransaction`, whose closure is `@Sendable`.
final class ConversationDeduplicationService: @unchecked Sendable {

    /// What one pass did, for logging and for tests.
    struct Outcome: Equatable {
        var mergedConversations = 0
        var movedMessages = 0
        /// Merges that kept the losing row as an alias because the server still
        /// lists it. Its history moved all the same — only the empty shell
        /// stayed, to absorb the sync that would otherwise recreate it.
        var aliasedServerRows = 0
    }

    private let database: any DatabaseRepositoryProtocol
    private let currentUserId: @Sendable () -> String

    init(
        database: any DatabaseRepositoryProtocol,
        currentUserId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.currentUid }
    ) {
        self.database = database
        self.currentUserId = currentUserId
    }

    // MARK: - Entry points

    /// Runs after each sync.
    ///
    /// Deliberately not gated behind a "have we done this once" flag. A flag
    /// makes the repair unrepeatable — it is consumed by the first run, even a
    /// run that happened before the rule was right, and every duplicate created
    /// afterwards then survives forever. The pass is idempotent and skips rows
    /// it has already merged, so running it again costs one participant query
    /// per conversation and changes nothing.
    @discardableResult
    func runIfNeeded() async -> Outcome? {
        // Without a session there is no "me", so no peer can be identified and
        // every direct conversation would look like it has the same peer.
        guard !currentUserId().isEmpty else { return nil }

        do {
            let outcome = try await run()
            debugLog(
                "merged=\(outcome.mergedConversations) movedMessages=\(outcome.movedMessages) "
                + "aliasedServerRows=\(outcome.aliasedServerRows)",
                category: "chat-dedup"
            )
            return outcome
        } catch {
            debugLog("failed: \(error)", category: "chat-dedup")
            return nil
        }
    }

    @discardableResult
    func run() async throws -> Outcome {
        // Rows already merged are skipped, not re-merged: an alias row stays in
        // the table on purpose, and without this a second pass would keep
        // finding the same pair and doing the work again.
        let conversations = try await database.fetch(ConversationModel.self, query: nil)
            .filter { $0.type == .direct && $0.mergedIntoId == nil }
        guard conversations.count > 1 else { return Outcome() }

        var identified: [(conversation: ConversationModel, identity: PeerIdentity)] = []
        for conversation in conversations {
            let identity = try await peerIdentity(for: conversation)
            guard !identity.isEmpty else { continue }
            identified.append((conversation, identity))
        }

        var outcome = Outcome()
        for group in PeerGrouping.groups(identified, identity: \.identity) where group.count > 1 {
            outcome = try await merge(group.map(\.conversation), into: outcome)
        }
        return outcome
    }

    // MARK: - Peer identity

    /// What makes two conversations the same conversation: the person on the
    /// other end — described by every identity we hold for them.
    ///
    /// The peer's own row is only half of it. A conversation started here knows
    /// a phone; the one the server sent knows an account id; the address book
    /// is what ties the two together, so it is consulted whenever the peer row
    /// is missing one of them. Without that, the two halves of the same
    /// conversation never recognise each other.
    private func peerIdentity(for conversation: ConversationModel) async throws -> PeerIdentity {
        let me = currentUserId()
        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversation.id)),
            limit: 10
        )
        let participants = try await database.fetch(ConversationParticipantModel.self, query: query)
        guard let peer = participants.first(where: { $0.userId != me && !$0.userId.isEmpty })
            ?? participants.first(where: { $0.userId != me })
        else { return PeerIdentity() }

        var identity = PeerIdentity(userId: peer.userId, phone: peer.phone)
        guard !identity.isEmpty else { return identity }

        if identity.userIds.isEmpty || identity.phones.isEmpty,
           let contact = try await contact(matching: identity) {
            identity.add(userId: contact.userId)
            identity.add(phone: contact.phone)
        }

        return identity
    }

    /// The address-book row for this peer, looked up by whichever half we have.
    private func contact(matching identity: PeerIdentity) async throws -> ContactModel? {
        if let userId = identity.userIds.first {
            let byUserId = QuerySpec(
                filter: FilterSpec("user_id == %@", .string(userId)),
                limit: 1
            )
            if let found = try await database.fetch(ContactModel.self, query: byUserId).first {
                return found
            }
        }

        guard let digits = identity.phones.first else { return nil }
        // Stored phones carry whatever formatting they arrived with, so the
        // match is on digits — which SQL cannot do for us here.
        let candidates = try await database.fetch(
            ContactModel.self,
            query: QuerySpec(limit: 500)
        )
        return candidates.first { PeerIdentity.phoneDigits($0.phone) == digits }
    }

    // MARK: - Merge

    private func merge(
        _ duplicates: [ConversationModel],
        into outcome: Outcome
    ) async throws -> Outcome {
        var outcome = outcome
        guard let survivor = Self.survivor(among: duplicates) else { return outcome }

        for loser in duplicates where loser.id != survivor.id {
            let moved = try await absorb(loser, into: survivor)
            outcome.movedMessages += moved
            outcome.mergedConversations += 1
            if loser.serverId != nil { outcome.aliasedServerRows += 1 }
        }

        return outcome
    }

    /// The row the others fold into: the one the server knows, else the one
    /// with the newest activity, else the oldest — a stable order, so a pass
    /// that runs twice picks the same winner both times.
    static func survivor(among duplicates: [ConversationModel]) -> ConversationModel? {
        duplicates.max { lhs, rhs in
            let lhsLinked = lhs.serverId != nil
            let rhsLinked = rhs.serverId != nil
            if lhsLinked != rhsLinked { return rhsLinked }

            let lhsActivity = lhs.lastMessageAt ?? lhs.createdAt
            let rhsActivity = rhs.lastMessageAt ?? rhs.createdAt
            if lhsActivity != rhsActivity { return lhsActivity < rhsActivity }

            return lhs.createdAt > rhs.createdAt
        }
    }

    /// Moves everything hanging off `loser` onto `survivor`, then drops it.
    ///
    /// Order matters twice over. Every child table cascades on delete, so
    /// anything still pointing at the loser when it goes is deleted with it —
    /// hence re-parent first, delete last.
    ///
    /// And deliberately *not* wrapped in `withTransaction`: that opens a
    /// savepoint named after the namespace, and every `save` below opens and
    /// releases a savepoint of the same name, so the first inner release
    /// destroys the outer one and the commit fails with "no such savepoint".
    /// Sequential writes are safe here because the pass is idempotent — a run
    /// interrupted halfway leaves the messages moved and the losing row still
    /// present, and the next run finishes the job.
    private func absorb(
        _ loser: ConversationModel,
        into survivor: ConversationModel
    ) async throws -> Int {
        let movedMessages = try await reparentMessages(from: loser.id, to: survivor.id)
        try await reparentReadReceipts(from: loser.id, to: survivor.id)
        try await reparentPinnedMessages(from: loser.id, to: survivor.id)
        try await reparentChatActions(from: loser.id, to: survivor.id)
        try await reparentCallLogs(from: loser.id, to: survivor.id)
        try await carryParticipant(from: loser.id, to: survivor.id)

        var merged = survivor
        merged.lastMessageAt = [merged.lastMessageAt, loser.lastMessageAt]
            .compactMap { $0 }
            .max()
        // Its messages now live under the survivor, so if the loser was the
        // livelier half its last message is the thread's last message.
        if (loser.lastMessageAt ?? .distantPast) > (survivor.lastMessageAt ?? .distantPast) {
            merged.lastMessageText = loser.lastMessageText
            merged.lastMessageType = loser.lastMessageType
            merged.lastMessageSenderName = loser.lastMessageSenderName
        }
        // Summed, not maxed: the two rows held different messages, so the
        // unread messages from this person are the total of both.
        merged.unreadCount += loser.unreadCount
        merged.isPinned = merged.isPinned || loser.isPinned
        merged.isArchived = merged.isArchived && loser.isArchived
        // An unsent draft is the user's own words: never drop one because
        // the row it was typed into lost the merge.
        if merged.draft?.isEmpty ?? true, let draft = loser.draft, !draft.isEmpty {
            merged.draft = draft
            merged.isShowingDraft = loser.isShowingDraft
        }
        if merged.title?.isEmpty ?? true { merged.title = loser.title }
        if merged.avatarURL?.isEmpty ?? true { merged.avatarURL = loser.avatarURL }
        merged.updatedAt = Date()

        try await database.save(merged)

        if loser.serverId == nil {
            try await database.delete(ConversationModel.self, id: loser.id)
        } else {
            // Emptied and pointed at the survivor. Everything that arrives
            // for this id from here on is redirected rather than hidden.
            var alias = loser
            alias.mergedIntoId = survivor.id
            alias.unreadCount = 0
            alias.draft = nil
            alias.isShowingDraft = false
            alias.updatedAt = Date()
            try await database.save(alias)
        }

        return movedMessages
    }

    // MARK: - Re-parenting

    private func reparentMessages(from losingId: String, to survivingId: String) async throws -> Int {
        // `MessageModel.id` is the codeMessage and the primary key, so the same
        // message cannot already sit under the survivor: these sets are disjoint
        // and every row moves.
        let messages = try await database.fetch(
            MessageModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string(losingId)))
        )
        for var message in messages {
            message.conversationId = survivingId
            try await database.save(message)
        }
        return messages.count
    }

    private func reparentReadReceipts(from losingId: String, to survivingId: String) async throws {
        let receipts = try await database.fetch(
            ReadReceiptModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string(losingId)))
        )
        for var receipt in receipts {
            receipt.conversationId = survivingId
            try await database.save(receipt)
        }
    }

    private func reparentPinnedMessages(from losingId: String, to survivingId: String) async throws {
        let pinned = try await database.fetch(
            PinnedMessageModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string(losingId)))
        )
        for var pin in pinned {
            pin.conversationId = survivingId
            try await database.save(pin)
        }
    }

    private func reparentChatActions(from losingId: String, to survivingId: String) async throws {
        let actions = try await database.fetch(
            ChatActionModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string(losingId)))
        )
        for action in actions {
            // Every field is `let`, so the row is rebuilt rather than mutated.
            let moved = ChatActionModel(
                id: action.id,
                conversationId: survivingId,
                actionType: action.actionType,
                targetId: action.targetId,
                performedBy: action.performedBy,
                metadataJSON: action.metadataJSON,
                timestamp: action.timestamp
            )
            try await database.save(moved)
        }
    }

    private func reparentCallLogs(from losingId: String, to survivingId: String) async throws {
        let calls = try await database.fetch(
            CallLogModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string(losingId)))
        )
        for var call in calls {
            call.conversationId = survivingId
            try await database.save(call)
        }
    }

    /// Gives the survivor a peer row if it somehow lacks one.
    ///
    /// The loser's own participants are cascade-deleted with it, so anything
    /// worth keeping has to be copied across first — and a survivor with no
    /// peer row is exactly the state that renders a nameless inbox entry.
    private func carryParticipant(from losingId: String, to survivingId: String) async throws {
        let me = currentUserId()
        let survivorPeers = try await database.fetch(
            ConversationParticipantModel.self,
            query: QuerySpec(
                filter: FilterSpec(
                    "conversation_id == %@ AND user_id != %@",
                    .string(survivingId),
                    .string(me)
                ),
                limit: 1
            )
        )
        guard survivorPeers.isEmpty else { return }

        let losingPeers = try await database.fetch(
            ConversationParticipantModel.self,
            query: QuerySpec(
                filter: FilterSpec(
                    "conversation_id == %@ AND user_id != %@",
                    .string(losingId),
                    .string(me)
                ),
                limit: 1
            )
        )
        guard var peer = losingPeers.first else { return }

        peer.id = ChatDeterministicId.uuid(from: "\(survivingId)_\(peer.userId)")
        peer.conversationId = survivingId
        peer.updatedAt = Date()
        try await database.save(peer)
    }
}
