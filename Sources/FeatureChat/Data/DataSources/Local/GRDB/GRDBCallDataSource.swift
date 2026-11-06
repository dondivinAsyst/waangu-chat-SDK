//
//  GRDBCallDataSource.swift
//  FeatureChat
//
//  Local store for the Calls tab, backed by the CallLogModel table.
//
//  Column names come verbatim from `CallLogModel.indexedFields` — the schema
//  builder does not snake_case them — so filters here read `status`,
//  `conversationId` and so on, matching the model's declaration exactly.
//

import Foundation
import WaanguCoreKit

final class GRDBCallDataSource: LocalCallDataSourceProtocol {

    private let store: any DatabaseRepositoryProtocol

    init(store: any DatabaseRepositoryProtocol) {
        self.store = store
    }

    // MARK: - Read

    func fetchAll(filter: CallLogFilter, limit: Int?) async throws -> [CallLogEntity] {
        let query: QuerySpec?

        switch filter {
        case .all:
            query = nil
        case .missed:
            // Both statuses mean "nobody picked up" and belong in the Missed tab.
            query = QuerySpec(
                filter: FilterSpec(
                    "status == %@ OR status == %@",
                    .string(CallStatusModel.missed.rawValue),
                    .string(CallStatusModel.noAnswer.rawValue)
                )
            )
        }

        let models = try await store.fetch(CallLogModel.self, query: query)
        return sortedNewestFirst(models, limit: limit)
    }

    func fetchOne(id: String) async throws -> CallLogEntity? {
        guard let model = try await store.fetchOne(CallLogModel.self, id: id) else { return nil }
        return CallMapper.toDomain(model)
    }

    func fetch(conversationId: String) async throws -> [CallLogEntity] {
        let query = QuerySpec(
            filter: FilterSpec("conversationId == %@", .string(conversationId))
        )
        let models = try await store.fetch(CallLogModel.self, query: query)
        return sortedNewestFirst(models, limit: nil)
    }

    // MARK: - Write

    func save(_ log: CallLogEntity) async throws {
        try await store.save(CallMapper.toModel(log))
    }

    func delete(id: String) async throws {
        try await store.delete(CallLogModel.self, id: id)
    }

    func delete(conversationId: String) async throws {
        let query = QuerySpec(
            filter: FilterSpec("conversationId == %@", .string(conversationId))
        )
        try await store.deleteAll(CallLogModel.self, query: query)
    }

    func deleteAll() async throws {
        try await store.deleteAll(CallLogModel.self, query: nil)
    }

    // MARK: - Ordering

    /// Sorts and truncates in Swift rather than through `SortSpec`.
    ///
    /// Indexed columns are created as TEXT, so an SQL `ORDER BY calledAt` would
    /// compare dates as strings and depend on the serialisation format staying
    /// lexicographically sortable. Comparing real `Date`s is correct whatever
    /// the engine writes, and a call log is a bounded list.
    private func sortedNewestFirst(_ models: [CallLogModel], limit: Int?) -> [CallLogEntity] {
        let sorted = models
            .sorted { $0.calledAt > $1.calledAt }
            .map(CallMapper.toDomain)

        guard let limit, limit < sorted.count else { return sorted }
        return Array(sorted.prefix(limit))
    }
}
