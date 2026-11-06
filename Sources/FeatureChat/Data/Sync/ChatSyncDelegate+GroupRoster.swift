import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: Group roster
// ─────────────────────────────────────────────────────────────
// A group event is two things at once: a line in the timeline, and a change to who
// is in the group. The timeline half rides the message path. This is the other
// half — without it the room shows "Marie was added" while the member list, the
// admin badges and the permission checks all still say otherwise.
//
// A group here is a `ConversationModel` with `type == .group`, and its members are
// `ConversationParticipantModel` rows — the same storage `GRDBGroupDataSource`
// reads, so applying the roster is what makes the group real on this device.

extension ChatSyncDelegate {

    func applyGroupRoster(
        _ event: ResolvedGroupEvent,
        conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async {
        await applyGroupMetadata(event, conversationId: conversationId, database: database)

        // What `targets` means is the event's to say. Creation carries the whole
        // group; the membership and role events carry only whoever they affected;
        // an update carries nobody. Reading it as a roster snapshot regardless
        // would leave a group with one member every time somebody was added.
        switch event.type {
        case .GROUP_CREATED, .USER_ADDED_TO_GROUP, .USER_JOINED_GROUP,
             .USER_PROMOTED_TO_ADMIN, .USER_DEMOTED_FROM_ADMIN:
            for participant in event.targets {
                await upsertGroupParticipant(
                    participant,
                    conversationId: conversationId,
                    database: database
                )
            }

        case .USER_REMOVED_FROM_GROUP:
            await markParticipantsLeft(
                event.targets,
                reason: .removed,
                conversationId: conversationId,
                database: database
            )

        case .USER_LEFT_GROUP:
            await markParticipantsLeft(
                event.targets,
                reason: .voluntary,
                conversationId: conversationId,
                database: database
            )

        default:
            break
        }
    }

    // MARK: - Private

    /// A group created or renamed elsewhere reaches this device as an event, and
    /// `ensureConversation` deliberately creates group rows with no title — so
    /// without this the group shows up unnamed until something else refetches it.
    ///
    /// Applied on every group event that carries a title, not just creation and
    /// rename: being *added* to a group is the first this device hears of it, and
    /// that payload names it too.
    private func applyGroupMetadata(
        _ event: ResolvedGroupEvent,
        conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async {
        guard var conversation = try? await database.fetchOne(
            ConversationModel.self,
            id: conversationId
        ) else { return }

        var changed = false
        // A group event is proof this is a group, whatever the envelope's shape
        // led `isGroupConversation` to guess from `receiverId` and `groupId`.
        if conversation.type != .group {
            conversation.type = .group
            changed = true
        }
        // `ensureConversation` marks inbound groups synced on the way in. Two cases
        // are left over for here:
        //
        // - a row it created as `.direct` because the payload's shape misled
        //   `isGroupConversation`, and that the flip above has just corrected —
        //   without this that row stays hidden from the list;
        // - a group whose creator was never known, because the first event this
        //   device saw of it was somebody being added rather than the creation.
        //   `GROUP_CREATED` names the creator outright and arrives later, and the
        //   synced flag alone used to stop it from ever being written down.
        let storedCreator = GroupMapper.createdBy(in: conversation.assignedAgentName)
        let eventCreator = creatorId(of: event)
        // Creation is authoritative about who created the group; anything else may
        // only fill in a blank.
        let adoptsEventCreator = !eventCreator.isEmpty
            && (storedCreator.isEmpty || event.type == .GROUP_CREATED)

        if !GroupMapper.isSyncedMetadata(conversation.assignedAgentName) || adoptsEventCreator {
            let metadata = GroupMapper.syncedMetadata(
                createdBy: adoptsEventCreator ? eventCreator : storedCreator,
                color: GroupMapper.color(in: conversation.assignedAgentName)
            )
            if metadata != conversation.assignedAgentName {
                conversation.assignedAgentName = metadata
                changed = true
            }
        }
        if let title = event.title, conversation.title != title {
            conversation.title = title
            changed = true
        }
        if let avatar = event.avatar, conversation.avatarURL != avatar {
            conversation.avatarURL = avatar
            changed = true
        }

        guard changed else { return }
        conversation.updatedAt = Date()
        try? await database.save(conversation)
    }

    /// Who created the group, as far as this event can say.
    ///
    /// Creation names the actor outright. Any later event has to fall back to
    /// whoever holds `OWNER` in the roster it carries, and to nothing at all when
    /// it carries no roster — `isCurrentUserAdmin` then falls through to the
    /// member roles, which are stored either way.
    private func creatorId(of event: ResolvedGroupEvent) -> String {
        if event.type == .GROUP_CREATED, !event.actorId.isEmpty {
            return event.actorId
        }
        return event.targets.first { $0.participantRole == .owner }?.userId ?? ""
    }

    private func upsertGroupParticipant(
        _ participant: GroupRosterParticipantDTO,
        conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async {
        let userId = participant.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userId.isEmpty else { return }

        let displayName = participant.displayName
        let phone = participant.phone ?? ""

        if var existing = await existingParticipant(
            userId: userId,
            conversationId: conversationId,
            database: database
        ) {
            existing.role = participant.participantRole
            if !displayName.isEmpty {
                existing.displayName = fieldCrypto.encrypt(displayName)
            }
            if existing.phone.isEmpty, !phone.isEmpty {
                existing.phone = phone
            }
            // Present in the roster means present in the group — this is what makes
            // a member who left and was re-added active again.
            existing.leftAt = nil
            existing.removedByUserId = nil
            existing.leaveReason = nil
            existing.updatedAt = Date()
            try? await database.save(existing)
            return
        }

        let model = ConversationParticipantModel(
            id: ChatDeterministicId.uuid(from: "\(conversationId)_\(userId)"),
            conversationId: conversationId,
            userId: userId,
            phone: phone,
            role: participant.participantRole,
            displayName: fieldCrypto.encrypt(displayName)
        )
        try? await database.save(model)
    }

    /// Departure is applied to whoever the event names, never by diffing a roster:
    /// a payload that only ever carries the affected member would otherwise read as
    /// "everyone else has gone".
    private func markParticipantsLeft(
        _ targets: [GroupRosterParticipantDTO],
        reason: LeaveReasonModel,
        conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async {
        for target in targets {
            let userId = target.userId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !userId.isEmpty,
                  var participant = await existingParticipant(
                      userId: userId,
                      conversationId: conversationId,
                      database: database
                  )
            else { continue }

            participant.leftAt = Date()
            participant.leaveReason = reason
            participant.updatedAt = Date()
            try? await database.save(participant)
        }
    }

    private func existingParticipant(
        userId: String,
        conversationId: String,
        database: any DatabaseRepositoryProtocol
    ) async -> ConversationParticipantModel? {
        let query = QuerySpec(
            filter: FilterSpec(
                "conversation_id == %@ AND user_id == %@",
                .string(conversationId),
                .string(userId)
            ),
            limit: 1
        )
        return try? await database.fetch(ConversationParticipantModel.self, query: query).first
    }
}
