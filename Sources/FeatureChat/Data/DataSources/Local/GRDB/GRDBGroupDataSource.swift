//
//  GRDBGroupDataSource.swift
//  FeatureChat
//
//  Adapted: GroupModel and GroupMemberModel are gone.
//  A group is a ConversationModel with type == .group.
//  Members are ConversationParticipantModel.
//  DiscussionModel is gone — messages are queried by conversationId directly.
//

import Foundation
import WaanguCoreKit

final class GRDBGroupDataSource: LocalGroupDataSourceProtocol {

    private let store: any DatabaseRepositoryProtocol
    private let fieldCrypto: any FieldEncryptionServiceProtocol

    init(store: any DatabaseRepositoryProtocol, fieldCrypto: any FieldEncryptionServiceProtocol) {
        self.fieldCrypto = fieldCrypto
        self.store = store
    }

    // MARK: - CRUD

    func save(_ group: GroupChat) async throws {
        // The row on disk owns the composer draft — `GroupChat` has no notion of
        // one, so a save rebuilt from it alone would erase what the user typed.
        let existing = try? await store.fetchOne(ConversationModel.self, id: group.localId)
        let conversation = GroupMapper.toConversation(
            group,
            draft: existing?.draft,
            isShowingDraft: existing?.isShowingDraft
        )
        try await store.save(conversation)
        try await saveSettings(group.settings, groupLocalId: conversation.id)
        try await replaceParticipants(group.members, conversationId: conversation.id)
    }

    func fetch(id: String) async throws -> GroupChat? {
        if let conversation = try await store.fetchOne(ConversationModel.self, id: id),
           conversation.type == .group {
            let members = try await fetchMembers(conversationId: id)
            return GroupMapper.toDomain(
                conversation,
                members: members,
                settings: try await fetchSettings(for: conversation)
            )
        }
        return try await fetchByServerId(id)
    }

    func fetchByLocalId(_ localId: String) async throws -> GroupChat? {
        guard let conversation = try await store.fetchOne(ConversationModel.self, id: localId),
              conversation.type == .group else {
            return nil
        }
        let members = try await fetchMembers(conversationId: localId)
        return GroupMapper.toDomain(
            conversation,
            members: members,
            settings: try await fetchSettings(for: conversation)
        )
    }

    func fetchByServerId(_ serverId: String) async throws -> GroupChat? {
        let query = QuerySpec(
            filter: FilterSpec(
                "type == %@ AND server_id == %@",
                .string(ConversationTypeModel.group.rawValue),
                .string(serverId)
            ),
            limit: 1
        )
        if let conversation = try await store.fetch(ConversationModel.self, query: query).first {
            let members = try await fetchMembers(conversationId: conversation.id)
            return GroupMapper.toDomain(
                conversation,
                members: members,
                settings: try await fetchSettings(for: conversation)
            )
        }

        // Legacy fallback: serverId packed in assignedAgentName index 3
        let groupsQuery = QuerySpec(filter: FilterSpec("type == %@", .string(ConversationTypeModel.group.rawValue)))
        let conversations = try await store.fetch(ConversationModel.self, query: groupsQuery)
        guard let conversation = conversations.first(where: { conv in
            let meta = (conv.assignedAgentName ?? "").components(separatedBy: "|")
            return meta.count >= 6 && meta[safe: 3] == serverId
        }) else { return nil }
        let members = try await fetchMembers(conversationId: conversation.id)
        return GroupMapper.toDomain(
            conversation,
            members: members,
            settings: try await fetchSettings(for: conversation)
        )
    }

    func fetchAll() async throws -> [GroupChat] {
        let query = QuerySpec(filter: FilterSpec("type == %@", .string(ConversationTypeModel.group.rawValue)))
        let conversations = try await store.fetch(ConversationModel.self, query: query)
        var groups: [GroupChat] = []
        for conversation in conversations {
            let members = try await fetchMembers(conversationId: conversation.id)
            groups.append(
                GroupMapper.toDomain(
                    conversation,
                    members: members,
                    settings: try await fetchSettings(for: conversation)
                )
            )
        }
        return groups
    }

    func fetchActive() async throws -> [GroupChat] {
        // isActive = synced AND not pending creation
        // We filter in-memory since sync state is packed in assignedAgentName
        let all = try await fetchAll()
        return all.filter { $0.isActive }
    }

    func fetchPending() async throws -> [GroupChat] {
        // isPending flag is packed as "1" in position [1] of assignedAgentName
        let all = try await fetchAll()
        return all.filter { $0.isPendingCreation && ($0.syncStatus == .pending || $0.syncStatus == .failed) }
    }

    func update(_ group: GroupChat) async throws {
        try await save(group)
    }

    func delete(id: String) async throws {
        guard let group = try await fetch(id: id) else { throw GroupError.notFound }
        let localId = group.localId

        // Delete messages in the conversation
        try await store.deleteAll(
            MessageModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string(localId)))
        )
        // Delete participants
        try await store.deleteAll(
            ConversationParticipantModel.self,
            query: QuerySpec(filter: FilterSpec("conversation_id == %@", .string(localId)))
        )
        // Delete permissions
        try await store.deleteAll(
            GroupPermissionsModel.self,
            query: QuerySpec(filter: FilterSpec("group_local_id == %@", .string(localId)))
        )
        // Delete settings
        try await store.deleteAll(
            GroupSettingsModel.self,
            query: QuerySpec(filter: FilterSpec("group_local_id == %@", .string(localId)))
        )
        // Delete the conversation
        try await store.delete(ConversationModel.self, id: localId)
    }

    // MARK: - Sync operations

    func activateGroup(localId: String, serverId: String) async throws {
        try await mutateGroup(localId: localId) { group in
            group.serverId = serverId
            group.isPendingCreation = false
            group.isActive = true
            group.syncStatus = .synced
            group.syncError = nil
            group.updatedAt = Date()
        }
    }

    func updateServerId(localId: String, serverId: String) async throws {
        try await mutateGroup(localId: localId) { group in
            group.serverId = serverId
            group.updatedAt = Date()
        }
    }

    func markSyncFailed(localId: String, error: String) async throws {
        try await mutateGroup(localId: localId) { group in
            group.syncStatus = .failed
            group.syncError = error
            group.updatedAt = Date()
        }
    }

    func markSyncSuccess(localId: String) async throws {
        try await mutateGroup(localId: localId) { group in
            group.syncStatus = .synced
            group.syncError = nil
            group.updatedAt = Date()
        }
    }

    func markSyncing(localId: String) async throws {
        try await mutateGroup(localId: localId) { group in
            group.syncStatus = .syncing
            group.updatedAt = Date()
        }
    }

    func incrementRetryCount(localId: String) async throws {
        try await mutateGroup(localId: localId) { group in
            group.retryCount += 1
            group.updatedAt = Date()
        }
    }

    // MARK: - Member operations

    func addMember(_ member: GroupMember, to groupId: String) async throws {
        guard let group = try await fetch(id: groupId) else { throw GroupError.notFound }
        let participant = GroupMapper.memberToParticipant(member, conversationId: group.localId)
        try await store.save(participant)
    }

    func removeMember(userId: String, from groupId: String) async throws {
        guard let group = try await fetch(id: groupId) else { throw GroupError.notFound }
        try await store.deleteAll(
            ConversationParticipantModel.self,
            query: QuerySpec(
                filter: FilterSpec(
                    "conversation_id == %@ AND user_id == %@",
                    .string(group.localId),
                    .string(userId)
                )
            )
        )
    }

    func deactivateMember(userId: String, from groupId: String) async throws {
        guard let group = try await fetch(id: groupId) else { throw GroupError.notFound }
        let query = QuerySpec(
            filter: FilterSpec(
                "conversation_id == %@ AND user_id == %@",
                .string(group.localId),
                .string(userId)
            ),
            limit: 1
        )
        guard let existing = try await store.fetch(ConversationParticipantModel.self, query: query).first else {
            throw GroupError.notFound
        }
        let deactivated = ConversationParticipantModel(
            id: existing.id,
            conversationId: existing.conversationId,
            userId: existing.userId,
            contactId: existing.contactId,
            phone: existing.phone,
            role: existing.role,
            displayName: existing.displayName,
            avatarURL: existing.avatarURL,
            joinedAt: existing.joinedAt,
            addedByUserId: existing.addedByUserId,
            leftAt: Date(),
            removedByUserId: existing.removedByUserId,
            leaveReason: .voluntary,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        try await store.save(deactivated)
    }

    func updateMember(_ member: GroupMember, in groupId: String) async throws {
        guard let group = try await fetch(id: groupId) else {
            throw GroupError.notFound
        }
        let participant = GroupMapper.memberToParticipant(member, conversationId: group.localId)
        try await store.save(participant)
    }

    // MARK: - Private helpers

    private func mutateGroup(localId: String, mutate: (inout GroupChat) -> Void) async throws {
        guard let group = try await fetchByLocalId(localId) else { throw GroupError.notFound }
        var mutableGroup = group
        mutate(&mutableGroup)
        try await save(mutableGroup)
    }

    /// Defaults when the group has no settings row yet — every read path treats a
    /// missing row the same way the old `draft` blob treated undecodable JSON.
    ///
    /// Falls back to that blob first, though: groups written before settings moved
    /// out of `draft` have no row here, and reading straight past them would reset
    /// every existing group's invite link and admin restrictions on upgrade. The
    /// legacy value is left where it is — the next `save` writes a proper row, and
    /// `isShowingDraft` is nil on those rows so the list never mistakes the JSON
    /// for a draft in the meantime.
    private func fetchSettings(for conversation: ConversationModel) async throws -> GroupSettings {
        if let model = try await store.fetchOne(GroupSettingsModel.self, id: conversation.id) {
            return model.settings
        }
        if let legacy = conversation.draft,
           conversation.isShowingDraft != true,
           let data = legacy.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(GroupSettings.self, from: data) {
            return decoded
        }
        return GroupSettings()
    }

    /// Silently skips an unencodable value rather than replacing a good row with
    /// an unreadable one.
    private func saveSettings(_ settings: GroupSettings, groupLocalId: String) async throws {
        guard let model = GroupSettingsModel.make(groupLocalId: groupLocalId, settings: settings) else {
            return
        }
        try await store.save(model)
    }

    private func fetchMembers(conversationId: String) async throws -> [GroupMember] {
        let query = QuerySpec(
            filter: FilterSpec("conversation_id == %@", .string(conversationId))
        )
        let participants = try await store.fetch(ConversationParticipantModel.self, query: query)
        return participants.map { GroupMapper.participantToMember($0,fieldCrypto: fieldCrypto) }
    }

    private func replaceParticipants(_ members: [GroupMember], conversationId: String) async throws {
        try await store.deleteAll(
            ConversationParticipantModel.self,
            query: QuerySpec(
                filter: FilterSpec("conversation_id == %@", .string(conversationId))
            )
        )
        for member in members {
            let participant = GroupMapper.memberToParticipant(member, conversationId: conversationId)
            try await store.save(participant)
        }
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
