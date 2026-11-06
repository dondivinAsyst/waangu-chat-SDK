//
//  LocalCallDataSourceProtocol.swift
//  FeatureChat
//

import Foundation

protocol LocalCallDataSourceProtocol {
    /// Newest first. `limit: nil` returns everything.
    func fetchAll(filter: CallLogFilter, limit: Int?) async throws -> [CallLogEntity]
    func fetchOne(id: String) async throws -> CallLogEntity?
    func fetch(conversationId: String) async throws -> [CallLogEntity]
    func save(_ log: CallLogEntity) async throws
    func delete(id: String) async throws
    func delete(conversationId: String) async throws
    func deleteAll() async throws
}
