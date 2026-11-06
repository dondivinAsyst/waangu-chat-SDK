//
//  GRDBStatusDataSource.swift
//  FeatureChat
//
//  Adapted to new StatusModel schema:
//  – StatusModel is now a per-segment record (no parent StatusModel + StatusItemModel split)
//  – StatusViewerModel replaces SeenUserModel
//  – StatusPrivacyModel, StatusMediaTypeModel, SyncStatusModel are typed enums
//

import Foundation
import WaanguCoreKit

final class GRDBStatusDataSource: LocalStatusDataSourceProtocol {

    private let store: any DatabaseRepositoryProtocol
    private let fieldCrypto: any FieldEncryptionServiceProtocol

    init(
        store: any DatabaseRepositoryProtocol,
        fieldCrypto: any FieldEncryptionServiceProtocol
    ) {
        self.store = store
        self.fieldCrypto = fieldCrypto
    }

    // MARK: - Status CRUD

    func fetchOwnStatus(userId: String) async throws -> Status? {
        let segments = try await fetchSegments(userId: userId)
            .filter { !$0.isExpired }

        guard !segments.isEmpty else { return nil }
        let items = try await mapSegmentsToDomain(segments)
            .sorted { ($0.createdAt) < ($1.createdAt) }
        // Own thread: open at 0 (or My Status list sets an explicit index). Not "resume unviewed".
        return Status(
            userId: userId,
            userName: segments.first?.userName,
            userImage: segments.first?.avatarURL,
            lastStatusTime: segments.map(\.postedAt).max(),
            viewed: segments.allSatisfy(\.viewed),
            currentIndex: 0,
            status: items
        )
        
    }

    func fetchContactStatuses() async throws -> [Status] {
        let currentUserId = CurrentSessionInfo.shared.currentUid
        let query = QuerySpec(
            filter: FilterSpec("user_id != %@", .string(currentUserId)),
            sort: [SortSpec("posted_at", ascending: false)]
        )
        let allSegments = try await store.fetch(StatusModel.self, query: query)
            .filter { !$0.isExpired }

        // Group by userId
        var grouped: [String: [StatusModel]] = [:]
        for segment in allSegments {
            grouped[segment.userId, default: []].append(segment)
        }

        var statuses: [Status] = []
        for (userId, segments) in grouped {
            guard !segments.isEmpty else { continue }
            let items = try await mapSegmentsToDomain(segments)
                .sorted { ($0.createdAt) < ($1.createdAt) }
            guard !items.isEmpty else { continue }
            statuses.append(Status(
                userId: userId,
                userName: segments.first?.userName,
                userImage: segments.first?.avatarURL,
                lastStatusTime: segments.map(\.postedAt).max(),
                viewed: items.allSatisfy(\.viewed),
                currentIndex: Status.resumeIndex(for: items),
                status: items
            ))
        }
        return statuses
    }

    func saveStatus(_ status: Status) async throws {
        for item in status.status {
            let model = StatusLocalMapper.toGRDB(item)
            try await store.save(model)
        }
    }

    func deleteStatus(userId: String) async throws {
        let segments = try await fetchSegments(userId: userId)
        for segment in segments {
            try await store.deleteAll(
                StatusViewerModel.self,
                query: QuerySpec(filter: FilterSpec("status_id == %@", .string(segment.id)))
            )
        }
        try await store.deleteAll(
            StatusModel.self,
            query: QuerySpec(filter: FilterSpec("user_id == %@", .string(userId)))
        )
    }

    func clearAllStatuses() async throws {
        try await store.deleteAll(StatusViewerModel.self, query: nil)
        try await store.deleteAll(StatusModel.self, query: nil)
    }

    // MARK: - StatusItem CRUD

    func fetchStatusItems(forUserId userId: String) async throws -> [StatusItem] {
        let segments = try await fetchSegments(userId: userId)
        return try await mapSegmentsToDomain(segments)
    }

    func saveStatusItem(_ item: StatusItem) async throws {
        let model = StatusLocalMapper.toGRDB(item)
        try await store.save(model)
    }

    func deleteStatusItem(_ id: String) async throws {
        try await store.deleteAll(
            StatusViewerModel.self,
            query: QuerySpec(filter: FilterSpec("status_id == %@", .string(id)))
        )
        try await store.delete(StatusModel.self, id: id)
    }

    func deleteExpiredStatuses() async throws {
        let now = Date()
        let query = QuerySpec(filter: FilterSpec("expires_at < %@", .date(now)))
        let expired = try await store.fetch(StatusModel.self, query: query)
        for segment in expired {
            try await store.deleteAll(
                StatusViewerModel.self,
                query: QuerySpec(filter: FilterSpec("status_id == %@", .string(segment.id)))
            )
            try await store.delete(StatusModel.self, id: segment.id)
        }
    }

    func updateStatusItem(_ item: StatusItem) async throws {
        let model = StatusLocalMapper.toGRDB(item)
        try await store.save(model)
    }

    @discardableResult
    func markStatusItemAsUploaded(itemId: String) async throws -> String? {
        guard var segment = try await store.fetchOne(StatusModel.self, id: itemId) else { return nil }
        segment.localPath = nil // uploaded — no longer need local path
        segment.syncStatus = .synced
        segment.updatedAt = Date()
        try await store.save(segment)
        return segment.userId
    }

    @discardableResult
    func markStatusItemAsPublished(itemId: String) async throws -> String? {
        // In the new model there is no separate isPublished flag.
        // Setting syncStatus = .synced is the equivalent.
        return try await markStatusItemAsUploaded(itemId: itemId)
    }

    func updateDuration() async throws {
        let myId = CurrentSessionInfo.shared.currentUid
        let query = QuerySpec(filter: FilterSpec("user_id != %@", .string(myId)))
        let segments = try await store.fetch(StatusModel.self, query: query)
        for var segment in segments {
            segment.durationSeconds = 5.0 // normalise to 5 s for contact statuses
            segment.updatedAt = Date()
            try await store.save(segment)
        }
    }

    // MARK: - Seen marking
    //
    // `viewed` = I (this device) opened this contact segment → drives the green ring.
    // `viewCount` = others watched *my* story → only bumped on inbound STORY_VIEWED.

    func markStatusItemViewedInDB(storyId: String, userId: String) async throws {
        guard var segment = try await resolveSegment(storyId: storyId) else { return }
        guard !segment.viewed else { return }
        segment.viewed = true
        segment.updatedAt = Date()
        try await store.save(segment)
    }

    func markStatusViewedInDB(userId: String) async throws {
        let segments = try await fetchSegments(userId: userId)
        for var segment in segments where !segment.viewed {
            segment.viewed = true
            segment.updatedAt = Date()
            try await store.save(segment)
        }
    }

    // MARK: - SeenUser / StatusViewer CRUD

    @discardableResult
    func addSeenUser(_ seenUser: SeenUser, statusItemId: String) async throws -> String? {
        guard let segment = try await store.fetchOne(StatusModel.self, id: statusItemId) else { return nil }
        let viewer = StatusLocalMapper.toViewerModel(
            from: seenUser,
            statusId: segment.id,
            fieldCrypto: fieldCrypto
        )
        try await store.save(viewer)
        return segment.userId
    }

    func fetchSeenUsers(forStatusItemId statusItemId: String) async throws -> [SeenUser] {
        let query = QuerySpec(
            filter: FilterSpec("status_id == %@", .string(statusItemId)),
            sort: [SortSpec("viewed_at", ascending: false)]
        )
        let viewers = try await store.fetch(StatusViewerModel.self, query: query)
        return viewers.map { StatusLocalMapper.toSeenUser($0, fieldCrypto: fieldCrypto) }
    }

    // MARK: - Sync queries

    func getPendingSyncStatuses(inBackground: Bool) async throws -> [StatusItem] {
        let pending   = SyncStatusModel.pending.rawValue
        let failed    = SyncStatusModel.failed.rawValue
        let syncing   = SyncStatusModel.syncing.rawValue

        let query: QuerySpec
        if inBackground {
            query = QuerySpec(
                filter: FilterSpec(
                    "sync_status == %@ OR sync_status == %@",
                    .string(pending),
                    .string(syncing)
                ),
                sort: [SortSpec("posted_at", ascending: true)]
            )
        } else {
            query = QuerySpec(
                filter: FilterSpec(
                    "sync_status == %@ OR sync_status == %@ OR sync_status == %@",
                    .string(pending),
                    .string(syncing),
                    .string(failed)
                ),
                sort: [SortSpec("posted_at", ascending: true)]
            )
        }
        let segments = try await store.fetch(StatusModel.self, query: query)
        return try await mapSegmentsToDomain(segments)
    }

    func getPendingSyncStatus(statusId: String) async throws -> StatusItem? {
        guard let segment = try await resolveSegment(storyId: statusId) else { return nil }
        let items = try await mapSegmentsToDomain([segment])
        return items.first
    }

    @discardableResult
    func updateSyncStatus(itemId: String, syncStatus: SyncStatus, errorMessage: String?) async throws -> String? {
        guard var segment = try await resolveSegment(storyId: itemId) else { return nil }
        segment.syncStatus = StatusLocalMapper.mapToSyncStatusModel(syncStatus)
        if syncStatus == .synced {
            segment.expiresAt = segment.postedAt.addingTimeInterval(24 * 3600)
        }
        segment.updatedAt = Date()
        try await store.save(segment)
        return segment.userId
    }

    // MARK: - Private helpers

    private func fetchSegments(userId: String) async throws -> [StatusModel] {
        let query = QuerySpec(
            filter: FilterSpec("user_id == %@", .string(userId)),
            sort: [SortSpec("segment_index", ascending: true)]
        )
        return try await store.fetch(StatusModel.self, query: query)
    }

    /// Resolve a segment by primary key (`id` == local `storyId` / `codeStatus`).
    private func resolveSegment(storyId: String) async throws -> StatusModel? {
        try await store.fetchOne(StatusModel.self, id: storyId)
    }

    private func mapSegmentsToDomain(_ segments: [StatusModel]) async throws -> [StatusItem] {
        var items: [StatusItem] = []
        for segment in segments {
            let viewerQuery = QuerySpec(
                filter: FilterSpec("status_id == %@", .string(segment.id)),
                sort: [SortSpec("viewed_at", ascending: false)]
            )
            let viewers = try await store.fetch(StatusViewerModel.self, query: viewerQuery)
            let seenUsers = viewers.map { StatusLocalMapper.toSeenUser($0, fieldCrypto: fieldCrypto) }

            items.append(StatusLocalMapper.toDomain(segment: segment, seenUsers: seenUsers))
        }
        return items
    }
}
