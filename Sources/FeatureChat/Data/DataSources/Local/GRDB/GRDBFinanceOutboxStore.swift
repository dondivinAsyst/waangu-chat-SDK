//
//  GRDBFinanceOutboxStore.swift
//  FeatureChat
//
//  Persistance de la file financière — Bloc 1, lot 2.3.
//

import Foundation
import WaanguCoreKit

/// Où `ChatFinanceOutbox` conserve ses actions.
///
/// Le compte est passé à chaque appel plutôt que fixé à la construction : la
/// file vit tout le processus, le compte change avec les connexions, et la purge
/// de déconnexion doit viser le compte qui part — que la session courante a
/// parfois déjà oublié.
protocol ChatFinanceOutboxStoring: Sendable {
    func load(accountID: String) async throws -> [ChatFinanceOutboxItem]
    func save(_ item: ChatFinanceOutboxItem, accountID: String) async throws
    func remove(id: String) async throws
    func clear(accountID: String) async throws
}

/// ``ChatFinanceOutboxStoring`` sur la base GRDB du chat.
final class GRDBFinanceOutboxStore: ChatFinanceOutboxStoring {

    private let store: any DatabaseRepositoryProtocol

    init(store: any DatabaseRepositoryProtocol) {
        self.store = store
    }

    /// Les actions du compte, dans l'ordre où elles ont été créées.
    func load(accountID: String) async throws -> [ChatFinanceOutboxItem] {
        try await store.fetch(FinanceOutboxItemModel.self, query: Self.query(accountID))
            .map(\.item)
            .sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ item: ChatFinanceOutboxItem, accountID: String) async throws {
        try await store.save(FinanceOutboxItemModel(accountID: accountID, item: item))
    }

    func remove(id: String) async throws {
        try await store.delete(FinanceOutboxItemModel.self, id: id)
    }

    func clear(accountID: String) async throws {
        try await store.deleteAll(FinanceOutboxItemModel.self, query: Self.query(accountID))
    }

    private static func query(_ accountID: String) -> QuerySpec {
        QuerySpec(filter: FilterSpec("account_id = %@", .string(accountID)))
    }
}
