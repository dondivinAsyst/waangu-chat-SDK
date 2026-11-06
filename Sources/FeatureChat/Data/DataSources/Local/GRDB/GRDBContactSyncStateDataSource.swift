//
//  GRDBContactSyncStateDataSource.swift
//  FeatureChat
//
//  GRDB implementation of LocalContactSyncStateDataSourceProtocol
//  Created by Kiro on 6/1/26.
//

import Foundation
import WaanguCoreKit

final class GRDBContactSyncStateDataSource: LocalContactSyncStateDataSourceProtocol {
    
    private let store: any DatabaseRepositoryProtocol
    private let namespace = "chat"
    
    init(store: any DatabaseRepositoryProtocol) {
        self.store = store
    }
    
    // MARK: - Protocol Implementation
    
    func fetchAllSyncStates() async throws -> [ContactSyncState] {
        let models = try await store.fetch(
            ContactSyncStateModel.self,
            query: nil
        )
        return models.compactMap { toDomain($0) }
    }
    
    func fetchSyncState(contactId: String) async throws -> ContactSyncState? {
        let query = QuerySpec(
            filter: FilterSpec("contact_id == %@", .string(contactId)),
            limit: 1
        )
        let models = try await store.fetch(
            ContactSyncStateModel.self,
            query: query
        )
        return models.first.flatMap { toDomain($0) }
    }
    
    func saveSyncState(_ state: ContactSyncState) async throws {
        let model = toGRDB(state)
        try await store.save(model)
    }
    
    func saveSyncStates(_ states: [ContactSyncState]) async throws {
        for state in states {
            let model = toGRDB(state)
            try await store.save(model)
        }
    }
    
    func deleteSyncState(contactId: String) async throws {
        let query = QuerySpec(
            filter: FilterSpec("contact_id == %@", .string(contactId))
        )
        try await store.deleteAll(
            ContactSyncStateModel.self,
            query: query
        )
    }
    
    func deleteSyncStates(contactIds: [String]) async throws {
        for contactId in contactIds {
            let query = QuerySpec(
                filter: FilterSpec("contact_id == %@", .string(contactId))
            )
            try await store.deleteAll(
                ContactSyncStateModel.self,
                query: query
            )
        }
    }
    
    func deleteAllSyncStates() async throws {
        try await store.deleteAll(
            ContactSyncStateModel.self,
            query: nil
        )
    }
    
    // MARK: - Mapping
    
    private func toGRDB(_ state: ContactSyncState) -> ContactSyncStateModel {
        return ContactSyncStateModel(
            id: state.contactId,
            contactId: state.contactId,
            rawPhone: state.rawPhone,
            normalizedPhone: state.normalizedPhone,
            contactHash: state.contactHash,
            lastSyncedAt: state.lastSyncedAt
        )
    }
    
    private func toDomain(_ model: ContactSyncStateModel) -> ContactSyncState? {
        guard let contactId = model.contactId,
              let rawPhone = model.rawPhone,
              let normalizedPhone = model.normalizedPhone,
              let contactHash = model.contactHash,
              let lastSyncedAt = model.lastSyncedAt else {
            return nil
        }
        
        return ContactSyncState(
            contactId: contactId,
            rawPhone: rawPhone,
            normalizedPhone: normalizedPhone,
            contactHash: contactHash,
            lastSyncedAt: lastSyncedAt
        )
    }
}
