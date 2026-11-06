//
//  CallSyncRepository.swift
//  FeatureChat
//
//  Server-side call history → local `CallLogModel` rows.
//  Endpoint: GET /api/v1/me/calls/sync
//
//  Same shape as `DiscussionRepository.syncConversations` and
//  `StatusRepository.syncStories`: pull a page, apply it, advance `since`,
//  repeat while `hasMore`. There is no cursor query parameter — paging happens
//  by moving `since` forward, so the loop has to derive the next instant itself.
//

import Foundation
import WaanguCoreKit

extension CallRepository {

    /// Pulls call history changed since the stored cursor.
    /// - Returns: how many call rows were written.
    func syncCalls(limit: Int) async throws -> Int {
        guard let remoteSyncDataSource, let syncCursorStore else {
            // No remote wired — the repository is running local-only.
            return 0
        }

        SyncHealthMonitor.shared.recordSyncStart(topic: .calls)

        // The stored cursor may be a timestamp or an opaque base64 token; both
        // reduce to an instant. Falling back to the plain last-sync date keeps a
        // device that has never parsed a cursor from re-pulling everything.
        var since: Date? = SinceCursor.date(from: syncCursorStore.getCallsCursor())
            ?? syncCursorStore.getCallsLastSyncDate()

        var totalSynced = 0
        var hasMore = true
        var pages = 0

        do {
            while hasMore, pages < Self.maxCallSyncPages {
                pages += 1

                let response = try await remoteSyncDataSource.syncCalls(since: since, limit: limit)

                guard let data = response.data else { break }

                var newestInPage: Date?
                for call in data.changedCalls ?? [] {
                    do {
                        try await applyChangedCall(call)
                        totalSynced += 1
                    } catch {
                        // One malformed call must not abandon the rest of the page.
                        debugLog("[CallsSync] Failed to apply call \(call.callId): \(error)")
                    }
                    if let at = call.watermark {
                        newestInPage = max(newestInPage ?? at, at)
                    }
                }

                hasMore = response.hasMore ?? false

                guard hasMore else {
                    // Finished: the server's clock is the watermark, never the
                    // device's — local skew would either re-pull forever or skip.
                    if let cursor = data.nextSinceCursor {
                        syncCursorStore.saveCallsCursor(cursor)
                    } else if let serverTime = data.serverTime {
                        syncCursorStore.saveCallsCursor(serverTime)
                    }
                    break
                }

                // More pages, and only `since` to get there.
                let advanced = SinceCursor.date(from: data.nextSinceCursor) ?? newestInPage

                // A `since` that does not move would re-request this very page.
                // Stop rather than loop — and deliberately without saving a
                // cursor, since the server just said there is more: recording
                // progress we did not make would skip it permanently.
                guard let advanced, since.map({ advanced > $0 }) ?? true else {
                    debugLog("[CallsSync] hasMore=true but cursor cannot advance — stopping")
                    break
                }

                if let cursor = data.nextSinceCursor {
                    syncCursorStore.saveCallsCursor(cursor)
                }
                since = advanced
            }

            SyncHealthMonitor.shared.recordSyncSuccess(topic: .calls, itemsSynced: totalSynced)

            if totalSynced > 0 {
                await MainActor.run {
                    NotificationCenter.default.post(name: .callHistoryPersisted, object: nil)
                }
            }
            return totalSynced

        } catch {
            SyncHealthMonitor.shared.recordSyncFailure(topic: .calls, error: error)
            throw error
        }
    }

    /// Guard against a server that never advances `since`.
    private static var maxCallSyncPages: Int { 200 }

    // MARK: - Applying one call

    private func applyChangedCall(_ dto: ChangedCallDTO) async throws {
        let callId = dto.callId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !callId.isEmpty else { return }

        let me = CurrentSessionInfo.shared.currentUid
        let everyone = mergedRoster(dto.participants ?? [], initiator: dto.initiator)
        let mine = everyone.first { $0.userId == me }
        let peer = everyone.first { $0.userId != me }
        let isGroupCall = everyone.count > 2
        let duration = max(dto.durationSec ?? 0, 0)
        let startedAt = dto.initiatedAtDate ?? dto.watermark ?? Date()

        let existing = try? await localDataSource.fetchOne(id: callId)

        // A call belongs to a conversation, always. If this device has not synced
        // that conversation yet, it is created here from what the call itself
        // knows — the calls tab is reachable before the chat list has ever been
        // opened, and a call log pointing at nothing is not a call log.
        let conversationId = await ensureConversationId(
            for: dto,
            isGroupCall: isGroupCall,
            peer: peer,
            startedAt: startedAt
        )

        // The payload names participants but not the contact record behind them,
        // and the avatar comes from contacts rather than the call. Neither is
        // overwritten with nothing when the row already carries one.
        let contactName = peer?.displayName?.isEmpty == false
            ? peer!.displayName!
            : (existing?.contactName ?? "")
        let contactPhone = peer?.phone?.isEmpty == false
            ? peer!.phone!
            : (existing?.contactPhone ?? "")

        let entity = CallLogEntity(
            id: callId,
            // A group call has no single other party; the list falls back to
            // `isGroupCall` and the participant count.
            userId: isGroupCall ? nil : peer?.userId,
            contactId: existing?.contactId,
            conversationId: conversationId,
            contactName: contactName,
            contactPhone: contactPhone,
            contactAvatarURL: existing?.contactAvatarURL,
            media: CallSyncVocabulary.media(dto.callType),
            direction: dto.initiator?.userId == me ? .outgoing : .incoming,
            outcome: CallSyncVocabulary.outcome(
                participantStatus: mine?.status,
                callStatus: dto.status,
                durationSeconds: duration
            ),
            durationSeconds: duration,
            startedAt: startedAt,
            endedAt: dto.endedAtDate ?? existing?.endedAt,
            isGroupCall: isGroupCall,
            groupName: existing?.groupName,
            participantCount: max(everyone.count, 1),
            initiatedByUserId: dto.initiator?.userId,
            participants: everyone.map {
                CallLogParticipant(
                    userId: $0.userId ?? "",
                    name: $0.displayName ?? "",
                    phone: $0.phone,
                    outcome: CallSyncVocabulary.outcome($0.status) ?? .missed
                )
            }
        )

        // Written straight through the local data source rather than
        // `saveCallLog`, which posts a refresh per row: one notification at the
        // end of the sync reloads the tab once instead of once per call.
        try await localDataSource.save(entity)
    }

    /// The initiator is already inside `participants` in every payload seen so
    /// far, but nothing promises it. Merging on id avoids both a duplicate and a
    /// call whose own initiator is missing from its roster.
    private func mergedRoster(
        _ participants: [CallSyncParticipantDTO],
        initiator: CallSyncParticipantDTO?
    ) -> [CallSyncParticipantDTO] {
        guard let initiator,
              let initiatorId = initiator.userId,
              !initiatorId.isEmpty else {
            return participants
        }
        if participants.contains(where: { $0.userId == initiatorId }) {
            return participants
        }
        return [initiator] + participants
    }

    /// The local conversation this call belongs to, creating it if this device
    /// has not seen it yet.
    ///
    /// `CallLogModel.conversationId` is a foreign key into the conversation
    /// table, so a call cannot be stored pointing at a row that is not there.
    /// Creating it is the right answer rather than dropping the link: the id in
    /// the payload is the same id the conversation sync uses as its primary key,
    /// so when that sync later runs it finds this row and fills in the title,
    /// avatar, participants and unread state instead of inserting a second one.
    ///
    /// What is written here is deliberately the minimum the call itself knows.
    /// No `lastMessageAt` in particular — a call is not a message, and dating the
    /// row would float an empty conversation to the top of the chat list.
    private func ensureConversationId(
        for dto: ChangedCallDTO,
        isGroupCall: Bool,
        peer: CallSyncParticipantDTO?,
        startedAt: Date
    ) async -> String? {
        let trimmed = dto.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, let database else { return nil }

        if (try? await database.fetchOne(ConversationModel.self, id: trimmed)) != nil {
            return trimmed
        }

        let query = QuerySpec(
            filter: FilterSpec("server_id == %@", .string(trimmed)),
            limit: 1
        )
        if let match = try? await database.fetch(ConversationModel.self, query: query).first {
            return match.id
        }

        let conversation = ConversationModel(
            id: trimmed,
            serverId: trimmed,
            // For a group the backend keys conversation and group on the same id.
            groupId: isGroupCall ? trimmed : nil,
            type: isGroupCall ? .group : .direct,
            // The call names the other party but never the group.
            title: isGroupCall ? nil : peer?.displayName,
            // Without synced metadata the chat list filters group rows out
            // entirely, so the group would exist and still be invisible.
            assignedAgentName: isGroupCall
                ? GroupMapper.syncedMetadata(createdBy: dto.initiator?.userId ?? "")
                : nil,
            createdAt: startedAt,
            updatedAt: Date()
        )

        do {
            try await database.save(conversation)
            return conversation.id
        } catch {
            debugLog("[CallsSync] Failed to create conversation \(trimmed): \(error)")
            return nil
        }
    }
}
