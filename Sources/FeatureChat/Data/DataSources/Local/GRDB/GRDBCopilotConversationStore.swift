//
//  GRDBCopilotConversationStore.swift
//  FeatureChat
//
//  La conversation Waangu Copilot dans la base du chat.
//

import Foundation
import WaanguCoreKit
import WaanguSharedUI

/// Une ligne `ConversationModel` de type `copilot` — la liste la lit comme les
/// autres — et ses messages dans `CopilotMessageModel`.
///
/// Un acteur : les ajouts arrivent dans l'ordre où Copilot les écrit, et la
/// position de chacun ne se calcule qu'une fois.
actor GRDBCopilotConversationStore: CopilotConversationStoring {

    private let store: any DatabaseRepositoryProtocol
    private let fieldCrypto: any FieldEncryptionServiceProtocol
    private let makeID: @Sendable () -> String
    /// Prochaine position, par conversation.
    private var nextPosition: [String: Int] = [:]

    init(store: any DatabaseRepositoryProtocol,
         fieldCrypto: any FieldEncryptionServiceProtocol,
         makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.store = store
        self.fieldCrypto = fieldCrypto
        self.makeID = makeID
    }

    func conversationID() async throws -> String {
        let query = QuerySpec(filter: FilterSpec("type == %@", .string(ConversationTypeModel.copilot.rawValue)))
        // La plus ancienne : `createdAt` n'est pas une colonne, le tri se fait ici.
        if let existing = try await store.fetch(ConversationModel.self, query: query)
            .min(by: { $0.createdAt < $1.createdAt }) {
            return existing.id
        }
        let now = Date()
        let conversation = ConversationModel(id: makeID(), type: .copilot, lastMessageAt: now,
                                             createdAt: now, updatedAt: now)
        try await store.save(conversation)
        await Self.refreshList()
        return conversation.id
    }

    func messages(in conversationID: String) async throws -> [Data] {
        try await store.fetch(CopilotMessageModel.self, query: Self.query(conversationID))
            .sorted { $0.position < $1.position }
            .compactMap { Data(base64Encoded: fieldCrypto.decrypt($0.payload)) }
    }

    func save(_ payload: Data, messageID: String, preview: String?, to conversationID: String) async throws {
        let encrypted = fieldCrypto.encrypt(payload.base64EncodedString())
        // Déjà là (une caméra qui vient de lire un code) : remplacé à sa place.
        if let existing = try await store.fetchOne(CopilotMessageModel.self, id: messageID) {
            try await store.save(CopilotMessageModel(
                id: messageID, conversationId: existing.conversationId, position: existing.position,
                payload: encrypted, createdAt: existing.createdAt))
            return
        }
        let position: Int
        if let next = nextPosition[conversationID] {
            position = next
        } else {
            position = try await store.count(CopilotMessageModel.self, query: Self.query(conversationID))
        }
        nextPosition[conversationID] = position + 1
        let now = Date()
        try await store.save(CopilotMessageModel(
            id: messageID, conversationId: conversationID, position: position,
            payload: encrypted, createdAt: now))

        guard var conversation = try await store.fetchOne(ConversationModel.self, id: conversationID) else { return }
        if let preview, !preview.isEmpty {
            conversation.lastMessageText = fieldCrypto.encrypt(preview)
            conversation.lastMessageType = .text
        }
        conversation.lastMessageAt = now
        conversation.updatedAt = now
        try await store.save(conversation)
        await Self.refreshList()
    }

    func delete(_ conversationID: String) async throws {
        try await store.deleteAll(CopilotMessageModel.self, query: Self.query(conversationID))
        try await store.delete(ConversationModel.self, id: conversationID)
        nextPosition[conversationID] = nil
        await Self.refreshList()
    }

    private static func query(_ conversationID: String) -> QuerySpec {
        QuerySpec(filter: FilterSpec("conversation_id == %@", .string(conversationID)))
    }

    /// La liste relit ses lignes : aperçu, heure, ou disparition.
    @MainActor private static func refreshList() {
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }
}
