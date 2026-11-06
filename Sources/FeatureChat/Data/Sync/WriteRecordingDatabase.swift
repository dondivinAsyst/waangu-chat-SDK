//
//  WriteRecordingDatabase.swift
//  FeatureChat
//
//  CHAT-FE-SDK-W360-B13, N-02 — rend visibles les écritures refusées.
//

import Foundation
import WaanguCoreKit

/// Transmet tout à la vraie base et retient la première erreur d'écriture.
///
/// `ChatSyncDelegate.processEvent` écrit à une trentaine d'endroits avec `try?` : une écriture
/// refusée disparaît sans trace. Au lieu de réécrire chacun de ces appels, on observe la base
/// qu'ils reçoivent. Seules les **écritures** sont suivies (`save`, `saveAll`, `delete`,
/// `deleteAll`, `withTransaction`) : une lecture qui échoue ne prouve pas qu'un événement
/// n'a pas été stocké.
actor WriteRecordingDatabase: DatabaseRepositoryProtocol {

    private let base: any DatabaseRepositoryProtocol
    private(set) var firstWriteError: String?

    init(wrapping base: any DatabaseRepositoryProtocol) { self.base = base }

    private func record(_ error: Error) {
        if firstWriteError == nil { firstWriteError = String(describing: type(of: error)) }
    }

    func save<T: Storable>(_ entity: T) async throws {
        do { try await base.save(entity) } catch { record(error); throw error }
    }
    func saveAll<T: Storable>(_ entities: [T]) async throws {
        do { try await base.saveAll(entities) } catch { record(error); throw error }
    }
    func delete<T: Storable>(_ type: T.Type, id: T.ID) async throws {
        do { try await base.delete(type, id: id) } catch { record(error); throw error }
    }
    func deleteAll<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws {
        do { try await base.deleteAll(type, query: query) } catch { record(error); throw error }
    }
    func withTransaction<R: Sendable>(_ block: @Sendable () async throws -> R) async throws -> R {
        do { return try await base.withTransaction(block) } catch { record(error); throw error }
    }
    func clearAll(namespace: String) async throws {
        do { try await base.clearAll(namespace: namespace) } catch { record(error); throw error }
    }

    func fetch<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws -> [T] {
        try await base.fetch(type, query: query)
    }
    func fetchOne<T: Storable>(_ type: T.Type, id: T.ID) async throws -> T? {
        try await base.fetchOne(type, id: id)
    }
    func count<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws -> Int {
        try await base.count(type, query: query)
    }
    func observe<T: Storable>(_ type: T.Type, query: QuerySpec?) -> AsyncStream<Result<[T], DatabaseError>> {
        let base = base
        return AsyncStream { continuation in
            Task {
                for await value in await base.observe(type, query: query) { continuation.yield(value) }
                continuation.finish()
            }
        }
    }
}
