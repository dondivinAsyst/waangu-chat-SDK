import Foundation
import Combine

public protocol StatusRepositoryProtocol {
    // Mark Update ui when there is some changes
    var statusUpdatedPublisher: Published<Status?>.Publisher { get }
    // Status
    func fetchOwnStatus(userId: String) async throws -> Status?
    func fetchContactStatuses() async throws -> [Status]
    func saveStatus(_ status: Status) async throws
    func deleteStatus(userId: String) async throws
    func clearAllStatuses() async throws
    
    // Status Items
    func fetchStatusItems(forUserId userId: String) async throws -> [StatusItem]
    func saveStatusItem(_ item: StatusItem) async throws
    func deleteStatusItem(_ id: String) async throws
    /// Smart delete: synced items → server DELETE first, then local; unsynced → local only.
    func deleteStatusItemSmart(_ id: String, syncStatus: SyncStatus, codeStatus: String) async throws
    func deleteExpiredStatuses() async throws
    func markStatusItemAsSeen(viewStory: ViewStory) async throws
    func markStatusAsSeen(viewStory: ViewStory) async throws
    func updateStatusItem(_ item: StatusItem) async throws
    func markStatusItemAsUploaded(itemId: String) async throws
    
    
    // Seen Users
    func addSeenUser(seenUser: SeenUser, statusItemId: String) async throws
    func fetchSeenUsers(forStatusItemId statusItemId: String) async throws -> [SeenUser]
    
    // Syncing
    func getLastSyncDate() throws -> Date?
    func updateLastSyncDate(_ date: Date) throws
    func getPendingSyncStatus(statusId: String) async throws -> StatusItem?
    
    func postOwnStatusToAPI(_ storyTosend: StoryToSend) async throws -> APIResponse
    func updateSyncStatus(for statusItemId: String, to syncStatus: SyncStatus, errorMessage: String?) async throws
    func getPendingSyncStatuses(inBackground: Bool) async throws -> [StatusItem]
    func getStatusFromServer() async throws
    func syncStories(limit: Int) async throws -> Int
}
