import Foundation
import Combine
import WaanguCoreKit
import WaanguNetworkKit

class StatusRepository: StatusRepositoryProtocol, ObservableObject {

    @Published private(set) var statusUpdated: Status?

    private let localDataSource: LocalStatusDataSourceProtocol
    private let httpDataSource: HTTPStatusDataSourceProtocol
    private let mapper: StatusMappersProtocol
    private let eventBus: ChatDomainEventBusProtocol
    private let syncCursorStore: SyncCursorStore
    private let database: any DatabaseRepositoryProtocol
    private let lastSyncKey = "lastSyncDate"

    var statusUpdatedPublisher: Published<Status?>.Publisher {
        $statusUpdated
    }

    init(
        localDataSource: LocalStatusDataSourceProtocol,
        httpDataSource: HTTPStatusDataSourceProtocol,
        mapper: StatusMappersProtocol,
        eventBus: ChatDomainEventBusProtocol,
        syncCursorStore: SyncCursorStore,
        database: any DatabaseRepositoryProtocol
    ) {
        self.localDataSource = localDataSource
        self.httpDataSource = httpDataSource
        self.mapper = mapper
        self.eventBus = eventBus
        self.syncCursorStore = syncCursorStore
        self.database = database
        subscriberToEvents()
    }

    // MARK: - Event Bus

    private func subscriberToEvents() {
        eventBus.subscribe { [weak self] event in
            self?.handleEvent(event)
        }
    }

    private func handleEvent(_ event: ChatDomainEvent) {
        switch event {
        case .newUserStatus(let statusItem):
            Task { [weak self] in
                guard let self, statusItem.userId != CurrentSessionInfo.shared.currentUid else { return }
                try? await self.saveStatusItem(statusItem)
            }

        case .userSeenMyownStatus(let statusItem):
            Task { [weak self] in
                guard let self, statusItem.userId != CurrentSessionInfo.shared.currentUid else { return }
                try? await self.updateStatusItem(statusItem)
            }
        }
    }

    // MARK: - Status (pass-through to local data source)

    func fetchOwnStatus(userId: String) async throws -> Status? {
        try await localDataSource.fetchOwnStatus(userId: userId)
    }

    func fetchContactStatuses() async throws -> [Status] {
        try await localDataSource.fetchContactStatuses()
    }

    func saveStatus(_ status: Status) async throws {
        try await localDataSource.saveStatus(status)
        if let first = status.status.first {
            self.statusUpdated = try await localDataSource.fetchOwnStatus(userId: first.userId)
        } else {
            self.statusUpdated = try await localDataSource.fetchOwnStatus(userId: status.userId)
        }
    }

    func deleteStatus(userId: String) async throws {
        try await localDataSource.deleteStatus(userId: userId)
        // Notify subscribers — after deletion own status may be nil or have fewer items
        self.statusUpdated = try await localDataSource.fetchOwnStatus(userId: userId)
    }

    func clearAllStatuses() async throws {
        try await localDataSource.clearAllStatuses()
        self.statusUpdated = nil
    }

    // MARK: - StatusItem (DB write + publisher refresh)

    func fetchStatusItems(forUserId userId: String) async throws -> [StatusItem] {
        try await localDataSource.fetchStatusItems(forUserId: userId)
    }

    func saveStatusItem(_ item: StatusItem) async throws {
        try await localDataSource.saveStatusItem(item)
        self.statusUpdated = try await localDataSource.fetchOwnStatus(userId: item.userId)
    }

    func deleteStatusItem(_ id: String) async throws {
        // Fetch the item first so we know the userId for the post-delete refresh
        let item = try await localDataSource.getPendingSyncStatus(statusId: id)
        try await localDataSource.deleteStatusItem(id)
        // Re-fetch and notify — if no items remain, statusUpdated = nil triggers ownStatus = nil
        let userId = item?.userId ?? CurrentSessionInfo.shared.currentUid
        self.statusUpdated = try await localDataSource.fetchOwnStatus(userId: userId)
    }

    /// Smart delete — routes based on sync state:
    ///   .synced → DELETE on server first, then remove locally (throws AppError if rejected)
    ///   anything else → local DB delete only (no network call)
    func deleteStatusItemSmart(_ id: String, syncStatus: SyncStatus, codeStatus: String) async throws {
        let userId: String

        if syncStatus == .synced {
            do {
                let request = DeleteStatusRequest(storyId: codeStatus)
                let response = try await httpDataSource.deleteStatus(request)
                guard response.isSuccess else {
                    // Never surface raw server `message` — use filtered AppError.
                    throw AppError.serverError
                }
            } catch let appError as AppError {
                throw appError
            } catch {
                throw APIErrorMapper().map(error)
            }
        }

        // Local delete (runs for both synced and unsynced)
        let item = try await localDataSource.getPendingSyncStatus(statusId: id)
        try await localDataSource.deleteStatusItem(id)
        userId = item?.userId ?? CurrentSessionInfo.shared.currentUid
        self.statusUpdated = try await localDataSource.fetchOwnStatus(userId: userId)
    }

    func deleteExpiredStatuses() async throws {
        try await localDataSource.deleteExpiredStatuses()
    }

    func updateStatusItem(_ item: StatusItem) async throws {
        try await localDataSource.updateStatusItem(item)
        if let refreshed = try? await localDataSource.fetchOwnStatus(userId: item.userId) {
            self.statusUpdated = refreshed
        }
    }

    func markStatusItemAsUploaded(itemId: String) async throws {
        if let userId = try await localDataSource.markStatusItemAsUploaded(itemId: itemId) {
            self.statusUpdated = try await localDataSource.fetchOwnStatus(userId: userId)
        }
    }

    func updateDuration() async throws {
        try await localDataSource.updateDuration()
    }

    // MARK: - Seen (MQTT + DB orchestration)

    func markStatusItemAsSeen(viewStory: ViewStory) async throws {
        try await localDataSource.markStatusItemViewedInDB(storyId: viewStory.storyId, userId: viewStory.userId)
    }

    func markStatusAsSeen(viewStory: ViewStory) async throws {
        try await localDataSource.markStatusViewedInDB(userId: viewStory.userId)
    }

    // MARK: - SeenUser

    func addSeenUser(seenUser: SeenUser, statusItemId: String) async throws {
        if let userId = try await localDataSource.addSeenUser(seenUser, statusItemId: statusItemId) {
            self.statusUpdated = try await localDataSource.fetchOwnStatus(userId: userId)
        }
    }

    func fetchSeenUsers(forStatusItemId statusItemId: String) async throws -> [SeenUser] {
        try await localDataSource.fetchSeenUsers(forStatusItemId: statusItemId)
    }

    // MARK: - Sync

    func getLastSyncDate() throws -> Date? {
        UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    func updateLastSyncDate(_ date: Date) throws {
        UserDefaults.standard.set(date, forKey: lastSyncKey)
    }

    func markStatusItemAsPublished(itemId: String) async throws {
        if let userId = try await localDataSource.markStatusItemAsPublished(itemId: itemId) {
            self.statusUpdated = try await localDataSource.fetchOwnStatus(userId: userId)
        }
    }

    func getPendingSyncStatuses(inBackground: Bool = false) async throws -> [StatusItem] {
        try await localDataSource.getPendingSyncStatuses(inBackground: inBackground)
    }

    func getPendingSyncStatus(statusId: String) async throws -> StatusItem? {
        try await localDataSource.getPendingSyncStatus(statusId: statusId)
    }

    func updateSyncStatus(for statusItemId: String, to syncStatus: SyncStatus, errorMessage: String? = nil) async throws {
        if let userId = try await localDataSource.updateSyncStatus(
            itemId: statusItemId,
            syncStatus: syncStatus,
            errorMessage: errorMessage
        ) {
            self.statusUpdated = try await localDataSource.fetchOwnStatus(userId: userId)
        }
    }

    // MARK: - Remote API

    func postOwnStatusToAPI(_ storyTosend: StoryToSend) async throws -> APIResponse {
        let request = CreateStatusRequest(from: storyTosend)

        do {
            let response = try await httpDataSource.onPostStatus(request)

            // Only mark published if the server accepted it
            if response.isSuccess {
                try await self.updateSyncStatus(for: storyTosend.id, to: .synced, errorMessage: nil)
            } else {
                try await self.updateSyncStatus(
                    for: storyTosend.id,
                    to: .failed,
                    errorMessage: response.message
                )
            }

            return response
        } catch {
            try await self.updateSyncStatus(
                for: storyTosend.id,
                to: .failed,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    func getStatusFromServer() async throws {
        let response: APIResponse = try await httpDataSource.getContactStatus()
        if !response.isSuccess {
            debugLog("Status fetch failed: \(response)")
        }
    }
    
    // MARK: - Stories Sync
    
    func syncStories(limit: Int) async throws -> Int {
        // ✅ Record sync start
        SyncHealthMonitor.shared.recordSyncStart(topic: .stories)
        
        // ✅ Load cursor from storage
        var since: Date? = nil
        if let lastCursor = syncCursorStore.getStoriesCursor(),
           let cursorDate = ISO8601DateFormatter().date(from: lastCursor) {
            since = cursorDate
            debugLog("[StoriesSync] Resuming from cursor: \(lastCursor)")
        } else if let lastSyncDate = syncCursorStore.getStoriesLastSyncDate() {
            since = lastSyncDate
            debugLog("[StoriesSync] Resuming from last sync: \(lastSyncDate)")
        } else {
            debugLog("[StoriesSync] No previous sync, starting from beginning")
        }
        
        var totalStoriesSynced = 0
        var hasMore = true
        var currentSince = since
        
        do {
            // Keep fetching while hasMore is true (pagination)
            while hasMore {
                let response = try await httpDataSource.syncStories(since: currentSince, limit: limit)
                
                guard let data = response.data else {
                    debugLog("[StoriesSync] No data in response")
                    break
                }
                
                // Bloc 8, §16 / P0-4-P0-5 — même règle que pour les
                // conversations : la page s'applique en une transaction (réelle
                // depuis B51), et un groupe qui échoue l'annule et empêche le
                // curseur d'avancer ; la page est rejouée.
                //
                // L'ancienne boucle écrivait un `print` et continuait ; le
                // curseur franchissait ensuite le groupe perdu, définitivement.
                var failedGroup: (String, Error)?
                var pageStories = 0

                try await database.withTransaction {
                    for storyGroup in data.changedStories {
                        do {
                            for story in storyGroup.stories {
                                try await processStory(story, from: storyGroup)
                                pageStories += 1
                            }
                        } catch {
                            failedGroup = (storyGroup.creatorId, error)
                        }
                    }

                    // Lever dans la transaction : c'est ce qui annule la page.
                    if let failed = failedGroup {
                        throw StoriesSyncError.pageNotFullyApplied(
                            failedCreatorID: failed.0,
                            underlying: failed.1
                        )
                    }
                }
                // Compté après le commit : une page annulée n'a rien synchronisé.
                totalStoriesSynced += pageStories

                // Check if there are more pages
                hasMore = data.hasMore ?? false
                
                // Update cursor for next iteration
                if let nextCursor = data.nextSinceCursor, hasMore {
                    syncCursorStore.saveStoriesCursor(nextCursor)
                    // B53 — même jeton opaque que pour les conversations : une
                    // position illisible arrête la pagination au lieu de la
                    // relancer depuis le début.
                    if let next = ISO8601Timestamp.date(from: nextCursor) {
                        currentSince = next
                    } else {
                        debugLog("next stories page cursor is not a date — paging stops (B53)", category: "sync")
                        hasMore = false
                    }
                } else {
                    // No more pages, save final cursor
                    if let nextCursor = data.nextSinceCursor {
                        syncCursorStore.saveStoriesCursor(nextCursor)
                    } else if let serverTime = data.serverTime {
                        syncCursorStore.saveStoriesCursor(serverTime)
                    }
                    hasMore = false
                }
            }
            
            // ✅ Record successful sync
            SyncHealthMonitor.shared.recordSyncSuccess(topic: .stories, itemsSynced: totalStoriesSynced)
            
            debugLog("[StoriesSync] ✅ Synced \(totalStoriesSynced) stories")
            return totalStoriesSynced
            
        } catch {
            // ✅ Record sync failure
            SyncHealthMonitor.shared.recordSyncFailure(topic: .stories, error: error)
            throw error
        }
    }
    
    private func processStory(_ story: StoryDTO, from group: ChangedStoryGroupDTO) async throws {
        // Parse dates
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let createdAt = formatter.date(from: story.createdAt ?? "") ?? Date()
        let expiresAt = formatter.date(from: story.expiresAt ?? "") ?? createdAt.addingTimeInterval(24 * 60 * 60)
        
        // Map media type
        let mediaType: StatusMediaTypeModel
        switch story.storyType?.lowercased() {
        case "text":
            mediaType = .text
        case "image":
            mediaType = .image
        case "video":
            mediaType = .video
        default:
            mediaType = .text
        }
        
        // Create or update StatusModel
        let statusModel = StatusModel(
            id: story.storyId,
            userId: story.creatorId,
            contactId: nil,
            userName: story.creatorDisplayName ?? group.creatorDisplayName ?? "Unknown",
            avatarURL: story.creatorAvatar ?? group.creatorAvatar,
            segmentIndex: 0, // Stories don't have segments in this API
            totalSegments: 1,
            mediaType: mediaType,
            text: story.content,
            caption: story.caption,
            linkURL: nil,
            mediaURL: story.content, // For image/video, content is the URL
            thumbnailURL: story.thumbnail,
            localPath: nil,
            mimeType: nil,
            backgroundColor: story.background,
            fontStyle: story.font,
            fontSize: nil,
            fontWeight: nil,
            width: nil,
            height: nil,
            durationSeconds: nil,
            privacy: .allContacts,
            allowedUserIds: nil,
            excludedUserIds: nil,
            viewCount: story.views?.count ?? 0,
            viewed: story.viewed ?? false,
            postedAt: createdAt,
            expiresAt: expiresAt,
            deletedAt: story.deleted == true ? (formatter.date(from: story.deletedAt ?? "") ?? Date()) : nil,
            syncStatus: .synced, // Already synced from server
            filename: nil,
            fileSize: 0,
            createdAt: createdAt,
            updatedAt: Date()
        )
        
        // Save to database
        try await database.save(statusModel)
    }
}


/// Bloc 8, P0-5 — une page de stories partiellement appliquée.
///
/// Typée plutôt qu'un `print` : la reprise consiste à re-télécharger la page,
/// et un appelant doit pouvoir le distinguer d'une panne réseau.
enum StoriesSyncError: Error {
    case pageNotFullyApplied(failedCreatorID: String, underlying: Error)
}
