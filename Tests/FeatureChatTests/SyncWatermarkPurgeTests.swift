//
//  SyncWatermarkPurgeTests.swift
//  FeatureChatTests
//
//  CHAT-FE-SDK-W360-B13, F-10 — les repères de synchro (`SyncState`) survivent
//  entre deux lancements, et la déconnexion les efface : ils sont rangés par
//  flux, pas par compte.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class SyncWatermarkPurgeTests: XCTestCase {

    private let streams = ["chat", "chat.conversations", "chat.calls"]

    /// `SyncState` vit dans sa propre base (namespace `sync`). Les migrations de champ du
    /// chat, passées à toutes les bases, y visaient une table `sync_statusmodels` qui n'existe
    /// pas : l'ouverture échouait et chaque écriture était avalée par un `try?`.
    func test_syncNamespace_isUsable_withTheChatMigrationSteps() async throws {
        let store = try await makeStore()
        var state = SyncState(feature: "chat-\(UUID().uuidString)")
        state.currentCursor = "cursor-1"

        try await store.save(state)

        let stored = try await store.fetchOne(SyncState.self, id: state.id)
        XCTAssertEqual(stored?.currentCursor, "cursor-1")
        try await store.delete(SyncState.self, id: state.id)
    }

    func test_clearSyncWatermarks_removesEveryStreamsWatermark() async throws {
        let store = try await makeStore()
        for id in streams {
            var state = SyncState(feature: id)
            state.lastSyncTimestamp = Date(timeIntervalSince1970: 1_791_000_000)
            state.currentCursor = "cursor-of-previous-account"
            try await store.save(state)
        }

        await ChatFeature.clearSyncWatermarks(in: store)

        for id in streams {
            let left = try await store.fetchOne(SyncState.self, id: id)
            XCTAssertNil(left, "\(id) would let the next account resume from this account's cursor")
        }
    }

    private func makeStore() async throws -> any DatabaseRepositoryProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }
}
