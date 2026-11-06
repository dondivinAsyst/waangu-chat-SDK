//
//  GRDBChatPreferenceDataSource.swift
//  FeatureChat
//
//  Reads/writes ChatPreferenceModel ↔ UserConversationSetting.
//  ChatPreferenceModel stores per-conversation preferences:
//  mute, pin, lock, wallpaper, ephemeral messages, auto-download, etc.
//

import Foundation
import WaanguCoreKit

final class GRDBChatPreferenceDataSource: LocalChatPreferenceDataSourceProtocol {

    private let store: any DatabaseRepositoryProtocol

    init(store: any DatabaseRepositoryProtocol) {
        self.store = store
    }

    // MARK: - Fetch

    func fetchPreference(conversationId: String) async throws -> UserConversationSetting? {
        guard let model = try await fetchModel(targetType: .conversation, targetKey: conversationId) else {
            return nil
        }
        return toDomain(model, key: conversationId)
    }

    func fetchPreference(phone: String) async throws -> UserConversationSetting? {
        guard let model = try await fetchModel(targetType: .direct, targetKey: phone) else {
            return nil
        }
        return toDomain(model, key: phone)
    }

    // MARK: - Save

    func savePreference(_ setting: UserConversationSetting, conversationId: String) async throws {
        let existing = try await fetchModel(targetType: .conversation, targetKey: conversationId)
        let model = makeConversationModel(from: setting, existing: existing, conversationId: conversationId)
        try await store.save(model)
    }

    func savePreference(_ setting: UserConversationSetting, phone: String) async throws {
        let existing = try await fetchModel(targetType: .direct, targetKey: phone)
        let model = makePhoneModel(from: setting, existing: existing, phone: phone)
        try await store.save(model)
    }

    // MARK: - Delete

    func deletePreference(conversationId: String) async throws {
        guard let existing = try await fetchModel(targetType: .conversation, targetKey: conversationId) else {
            return
        }
        try await store.delete(ChatPreferenceModel.self, id: existing.id)
    }

    // MARK: - Private helpers

    private func fetchModel(
        targetType: PreferenceTargetTypeModel,
        targetKey: String
    ) async throws -> ChatPreferenceModel? {
        let query = QuerySpec(
            filter: FilterSpec(
                "target_type == %@ AND target_key == %@",
                .string(targetType.rawValue),
                .string(targetKey)
            ),
            limit: 1
        )
        return try await store.fetch(ChatPreferenceModel.self, query: query).first
    }

    // MARK: - Domain mapping

    private func toDomain(_ model: ChatPreferenceModel, key: String) -> UserConversationSetting {
        var setting = UserConversationSetting()
        setting.conversation            = key
        setting.isMuted                 = model.isMuted
        setting.muteEndAt               = model.mutedUntil
        setting.isPinned                = model.isPinned
        setting.ephemeralMessageDuration = model.disappearingMessagesSeconds
        setting.updatedAt               = model.updatedAt
        return setting
    }

    private func makeConversationModel(
        from setting: UserConversationSetting,
        existing: ChatPreferenceModel?,
        conversationId: String
    ) -> ChatPreferenceModel {
        let isMuted    = setting.isMuted    ?? existing?.isMuted    ?? false
        let muteEnd    = setting.muteEndAt  ?? existing?.mutedUntil
        let isPinned   = setting.isPinned   ?? existing?.isPinned   ?? false
        let ephemeral  = setting.ephemeralMessageDuration ?? existing?.disappearingMessagesSeconds
        let createdAt  = existing?.createdAt ?? Date()

        return ChatPreferenceModel(
            conversationId: conversationId,
            isMuted: isMuted,
            mutedUntil: muteEnd,
            disappearingMessagesSeconds: ephemeral,
            isPinned: isPinned,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    private func makePhoneModel(
        from setting: UserConversationSetting,
        existing: ChatPreferenceModel?,
        phone: String
    ) -> ChatPreferenceModel {
        let isMuted    = setting.isMuted    ?? existing?.isMuted    ?? false
        let muteEnd    = setting.muteEndAt  ?? existing?.mutedUntil
        let isPinned   = setting.isPinned   ?? existing?.isPinned   ?? false
        let ephemeral  = setting.ephemeralMessageDuration ?? existing?.disappearingMessagesSeconds
        let createdAt  = existing?.createdAt ?? Date()

        return ChatPreferenceModel(
            phone: phone,
            isMuted: isMuted,
            mutedUntil: muteEnd,
            disappearingMessagesSeconds: ephemeral,
            isPinned: isPinned,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}
