//
//  MessageSearchTests.swift
//  FeatureChatTests
//
//  Harness 360 — matrice miroir : recherche.
//  La recherche globale lit les 500 messages les plus récents de la vraie base
//  SQLite et compare le texte **déchiffré** ; la recherche dans un fil filtre
//  les messages déjà affichés.
//
//  Un message supprimé n'est jamais retrouvé (B44) : la suppression garde
//  `content`, la recherche doit donc écarter les lignes `isDeleted`.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

@MainActor
final class MessageSearchTests: XCTestCase {

    // MARK: - Recherche globale

    func test_globalSearch_matchesCaseInsensitively_acrossConversations() async throws {
        let store = await Self.makeStore()
        let first = try await seedMessage("Rendez-vous au Marché-\(token) demain", in: store)
        let second = try await seedMessage("le marché-\(token) ferme à 18h", in: store)
        _ = try await seedMessage("rien à voir \(token)", in: store)

        let results = await search("marché-\(token)", in: store)

        XCTAssertEqual(Set(results.map(\.id)), [first.id, second.id])
        XCTAssertEqual(Set(results.map(\.conversationId)), [first.conversationId, second.conversationId])
    }

    /// Le texte est stocké chiffré champ par champ : la recherche compare le clair.
    func test_globalSearch_matchesTheDecryptedText_notTheStoredOne() async throws {
        let store = await Self.makeStore()
        let crypto = TaggingFieldCrypto()
        let message = try await seedMessage(crypto.encrypt("facture de juin \(token)"), in: store)

        let results = await search("juin \(token)", in: store, crypto: crypto)

        XCTAssertEqual(results.map(\.id), [message.id])
        XCTAssertEqual(results.first?.matchedText, "facture de juin \(token)")
    }

    func test_globalSearch_ignoresQueriesShorterThanTwoCharacters() async throws {
        let store = await Self.makeStore()
        _ = try await seedMessage("a", in: store)

        let results = await search(" a ", in: store)

        XCTAssertTrue(results.isEmpty)
    }

    /// Un message supprimé pour tous n'est plus retrouvable (B44).
    func test_messageDeletedForEveryone_isNotFound() async throws {
        let store = await Self.makeStore()
        _ = try await seedMessage("code secret \(token)", in: store, deleted: .forEveryone)
        let kept = try await seedMessage("code public \(token)", in: store)

        let results = await search(token, in: store)

        XCTAssertEqual(results.map(\.id), [kept.id])
    }

    /// « Supprimer pour moi » : je l'ai masqué, la recherche ne le rend pas.
    func test_messageDeletedForMe_isNotFound() async throws {
        let store = await Self.makeStore()
        _ = try await seedMessage("liste de courses \(token)", in: store, deleted: .forMe)

        let results = await search(token, in: store)

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Recherche dans un fil

    func test_inChatSearch_startsOnTheNewestMatch_andWrapsBothWays() async {
        let viewModel = MessageSearchViewModel(searchableStore: await Self.makeStore(), fieldCrypto: TaggingFieldCrypto())
        let messages = ["Bonjour", "bonne journée", "merci", "BONSOIR"].enumerated().map { index, text in
            MessageDataItem(codeMessage: "m\(index)", message: MessageContent(text: text),
                            createdAt: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        viewModel.searchText = "bon"
        viewModel.searchInChat(messages: messages)

        XCTAssertEqual(viewModel.inChatResults.map(\.codeMessage), ["m0", "m1", "m3"])
        XCTAssertEqual(viewModel.currentResultMessage?.codeMessage, "m3")
        viewModel.nextResult()
        XCTAssertEqual(viewModel.currentResultMessage?.codeMessage, "m0")
        viewModel.previousResult()
        XCTAssertEqual(viewModel.currentResultMessage?.codeMessage, "m3")
    }

    func test_clearSearch_resetsEverything() async {
        let viewModel = MessageSearchViewModel(searchableStore: await Self.makeStore(), fieldCrypto: TaggingFieldCrypto())
        viewModel.searchText = "bon"
        viewModel.searchInChat(messages: [MessageDataItem(codeMessage: "m0", message: MessageContent(text: "bonjour"), createdAt: Date())])

        viewModel.clearSearch()

        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertTrue(viewModel.inChatResults.isEmpty)
        XCTAssertNil(viewModel.currentResultMessage)
        XCTAssertFalse(viewModel.isSearching)
    }

    // MARK: - Outils

    private enum Deletion { case forMe, forEveryone }

    /// La base de test est un fichier qui survit d'un lancement à l'autre :
    /// chaque test cherche un jeton qui n'appartient qu'à lui.
    private let token = UUID().uuidString.prefix(8).lowercased()

    private func seedMessage(
        _ storedText: String,
        in store: any DatabaseRepositoryProtocol,
        deleted: Deletion? = nil
    ) async throws -> MessageModel {
        // Un message n'existe qu'avec sa conversation (clé étrangère).
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        try await store.save(conversation)
        let message = MessageModel(conversationId: conversation.id, senderId: "peer", senderName: "Peer",
                                   content: .text(storedText), deliveryStatus: .delivered,
                                   isDeleted: deleted != nil, isDeletedForAll: deleted == .forEveryone)
        try await store.save(message)
        return message
    }

    /// `searchAllChats` lance sa propre tâche ; on attend qu'elle rende la main.
    private func search(
        _ query: String,
        in store: any SearchableDatabaseProtocol,
        crypto: any FieldEncryptionServiceProtocol = TaggingFieldCrypto()
    ) async -> [MessageSearchResult] {
        let viewModel = MessageSearchViewModel(searchableStore: store, fieldCrypto: crypto)
        viewModel.searchText = query
        viewModel.searchAllChats()
        let deadline = Date().addingTimeInterval(5)
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

// MARK: - Doublures

/// Chiffrement visible : `enc:` + texte. Le déchiffrement retire le préfixe, et
/// laisse intact un texte qui n'en porte pas.
private struct TaggingFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { "enc:" + String(value.reversed()) }
    func decrypt(_ value: String) -> String {
        value.hasPrefix("enc:") ? String(value.dropFirst(4).reversed()) : value
    }
    func encryptOptional(_ value: String?) -> String? { value.map(encrypt) }
    func decryptOptional(_ value: String?) -> String? { value.map(decrypt) }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
