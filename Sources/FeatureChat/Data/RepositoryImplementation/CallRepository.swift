//
//  CallRepository.swift
//  FeatureChat
//
//  Every entry is written by this device as a call ends, and server-side history
//  merges in on top through `syncCalls` (see CallSyncRepository.swift) — same id
//  space, so a call this device logged and the server's record of it are one row.
//

import Foundation
import WaanguCoreKit

final class CallRepository: CallRepositoryProtocol {

    /// Not private: the sync half of this repository lives in its own file and
    /// writes through the same local data source, so one call reaches storage
    /// by exactly one path whether it was lived on this device or pulled.
    let localDataSource: LocalCallDataSourceProtocol
    let remoteSyncDataSource: RemoteCallSyncDataSourceProtocol?
    let syncCursorStore: SyncCursorStore?
    /// Only used to check that a conversation exists before a call points at it.
    let database: (any DatabaseRepositoryProtocol)?

    init(
        localDataSource: LocalCallDataSourceProtocol,
        remoteSyncDataSource: RemoteCallSyncDataSourceProtocol? = nil,
        syncCursorStore: SyncCursorStore? = nil,
        database: (any DatabaseRepositoryProtocol)? = nil
    ) {
        self.localDataSource = localDataSource
        self.remoteSyncDataSource = remoteSyncDataSource
        self.syncCursorStore = syncCursorStore
        self.database = database
    }

    func getCallLogs(filter: CallLogFilter, limit: Int?) async throws -> [CallLogEntity] {
        try await localDataSource.fetchAll(filter: filter, limit: limit)
    }

    func getCallLog(id: String) async throws -> CallLogEntity? {
        try await localDataSource.fetchOne(id: id)
    }

    func getCallLogs(conversationId: String) async throws -> [CallLogEntity] {
        try await localDataSource.fetch(conversationId: conversationId)
    }

    func saveCallLog(_ log: CallLogEntity) async throws {
        try await localDataSource.save(log)
        await MainActor.run {
            NotificationCenter.default.post(name: .callHistoryPersisted, object: nil)
        }
    }

    func deleteCallLog(id: String) async throws {
        try await localDataSource.delete(id: id)
        await MainActor.run {
            NotificationCenter.default.post(name: .callHistoryPersisted, object: nil)
        }
    }

    func deleteCallLogs(conversationId: String) async throws {
        try await localDataSource.delete(conversationId: conversationId)
        await MainActor.run {
            NotificationCenter.default.post(name: .callHistoryPersisted, object: nil)
        }
    }

    func clearCallLogs() async throws {
        try await localDataSource.deleteAll()
        await MainActor.run {
            NotificationCenter.default.post(name: .callHistoryPersisted, object: nil)
        }
    }
}
