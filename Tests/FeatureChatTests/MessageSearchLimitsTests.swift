//
//  MessageSearchLimitsTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 2.10 — ce que la recherche globale couvre et ce qu'elle ne couvre pas.
//
//  `MessageSearchViewModel.searchAllChats` lit les 500 messages non supprimés les plus récents de
//  **toute** la base locale, compare le texte déchiffré, et rend au plus 100 résultats. Il n'y a
//  aucun filtre de propriétaire ni de conversation : l'étanchéité entre comptes repose sur la
//  purge de la base au changement de compte ou de locataire (étapes 1.4 et 2.9).
//
//  Ces tests fixent ces limites pour qu'un changement soit voulu. Ils ne disent pas qu'elles
//  sont souhaitables.
//
//  La base de test est un fichier partagé qui survit d'un lancement à l'autre : les messages de
//  remplissage sont **plus anciens** que ceux des autres tests (ils ne peuvent pas les repousser
//  hors de la fenêtre) et sont supprimés à la fin.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

@MainActor
final class MessageSearchLimitsTests: XCTestCase {

    private let token = UUID().uuidString.prefix(8).lowercased()

    // MARK: Fenêtre des 500 messages

    func test_aMessageOlderThanTheNewest500_isNotFound() async throws {
        let store = await Self.makeStore()
        let conversation = try await seedConversation(in: store)
        let old = try await seed("ancien \(token)", in: store, conversation: conversation, ageSeconds: 5_000)
        try await seedFillers(500, in: store, conversation: conversation, youngerThanSeconds: 1_000)

        let results = await search(token, in: store)

        XCTAssertTrue(results.isEmpty, "le message le plus ancien est hors de la fenêtre : \(old.id)")
    }

    func test_aMessageInsideTheNewest500_isFound() async throws {
        let store = await Self.makeStore()
        let conversation = try await seedConversation(in: store)
        let recent = try await seed("récent \(token)", in: store, conversation: conversation, ageSeconds: 5)

        let results = await search(token, in: store)

        XCTAssertEqual(results.map(\.id), [recent.id])
    }

    // MARK: Au plus 100 résultats

    func test_resultsAreCappedAt100_keepingTheNewest() async throws {
        let store = await Self.makeStore()
        let conversation = try await seedConversation(in: store)
        var ids: [String] = []
        for index in 0..<101 {
            // Plus l'indice est grand, plus le message est ancien.
            ids.append(try await seed("résultat \(token) \(index)", in: store, conversation: conversation,
                                      ageSeconds: Double(10 + index)).id)
        }

        let results = await search(token, in: store)

        XCTAssertEqual(results.count, 100)
        XCTAssertFalse(results.map(\.id).contains(ids[100]), "le 101e, le plus ancien, est écarté")
        XCTAssertTrue(results.map(\.id).contains(ids[0]))
    }

    // MARK: Aucun filtre de conversation

    /// Une conversation archivée ou de groupe est cherchée comme les autres : seule la suppression
    /// d'un message l'écarte.
    func test_archivedAndGroupConversations_areSearchedToo() async throws {
        let store = await Self.makeStore()
        let archived = try await seedConversation(in: store, archived: true)
        let group = try await seedConversation(in: store, type: .group)
        let inArchived = try await seed("archivé \(token)", in: store, conversation: archived, ageSeconds: 3)
        let inGroup = try await seed("groupe \(token)", in: store, conversation: group, ageSeconds: 4)

        let results = await search(token, in: store)

        XCTAssertEqual(Set(results.map(\.id)), [inArchived.id, inGroup.id])
    }

    /// Constat : rien ici ne tient compte de l'appartenance. Un message resté dans la base d'une
    /// conversation que l'utilisateur a quittée, ou dont il a été retiré, se retrouve par la
    /// recherche. Le serveur doit signaler la perte d'appartenance pour que l'appareil purge
    /// (événement de membre, voir l'étape 3.2) ; il n'est pas appliqué aujourd'hui.
    func test_aMessageOfAConversationTheUserNoLongerBelongsTo_isStillFound() async throws {
        let store = await Self.makeStore()
        let left = try await seedConversation(in: store, type: .group)
        let message = try await seed("quitté \(token)", in: store, conversation: left, ageSeconds: 2)

        let results = await search(token, in: store)

        XCTAssertEqual(results.map(\.id), [message.id])
    }

    // MARK: Outils

    private func seedConversation(in store: any DatabaseRepositoryProtocol,
                                  type: ConversationTypeModel = .direct,
                                  archived: Bool = false) async throws -> ConversationModel {
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: type, isArchived: archived)
        try await store.save(conversation)
        addTeardownBlock { try? await store.delete(ConversationModel.self, id: conversation.id) }
        return conversation
    }

    @discardableResult
    private func seed(_ text: String, in store: any DatabaseRepositoryProtocol,
                      conversation: ConversationModel, ageSeconds: Double) async throws -> MessageModel {
        let message = MessageModel(conversationId: conversation.id, senderId: "peer", senderName: "Peer",
                                   content: .text(text),
                                   timestamp: Date().addingTimeInterval(-ageSeconds),
                                   deliveryStatus: .delivered)
        try await store.save(message)
        addTeardownBlock { try? await store.delete(MessageModel.self, id: message.id) }
        return message
    }

    /// Des messages qui ne contiennent pas le jeton, tous plus récents que le message à cacher.
    private func seedFillers(_ count: Int, in store: any DatabaseRepositoryProtocol,
                             conversation: ConversationModel, youngerThanSeconds age: Double) async throws {
        for index in 0..<count {
            try await seed("remplissage \(index)", in: store, conversation: conversation,
                           ageSeconds: age - Double(index) * 0.001)
        }
    }

    private func search(_ query: String, in store: any SearchableDatabaseProtocol) async -> [MessageSearchResult] {
        let viewModel = MessageSearchViewModel(searchableStore: store, fieldCrypto: PlainFieldCrypto())
        viewModel.searchText = query
        viewModel.searchAllChats()
        let deadline = Date().addingTimeInterval(10)
        repeat { await Task.yield() } while viewModel.isSearching && Date() < deadline
        XCTAssertFalse(viewModel.isSearching, "search did not finish in time")
        return viewModel.results
    }

    private static func makeStore() async -> any SearchableDatabaseProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }
}

private struct PlainFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
