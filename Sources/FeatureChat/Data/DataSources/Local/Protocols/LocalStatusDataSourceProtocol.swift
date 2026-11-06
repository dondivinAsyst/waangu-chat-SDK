import Foundation

protocol LocalStatusDataSourceProtocol {

    // MARK: - Status CRUD
    func fetchOwnStatus(userId: String) async throws -> Status?
    func fetchContactStatuses() async throws -> [Status]
    func saveStatus(_ status: Status) async throws
    func deleteStatus(userId: String) async throws
    func clearAllStatuses() async throws

    // MARK: - StatusItem CRUD
    func fetchStatusItems(forUserId userId: String) async throws -> [StatusItem]
    func saveStatusItem(_ item: StatusItem) async throws
    func deleteStatusItem(_ id: String) async throws
    func deleteExpiredStatuses() async throws
    func updateStatusItem(_ item: StatusItem) async throws

    /// Returns the userId of the item so the caller can refresh state.
    @discardableResult
    func markStatusItemAsUploaded(itemId: String) async throws -> String?

    /// Returns the userId of the item so the caller can refresh state.
    @discardableResult
    func markStatusItemAsPublished(itemId: String) async throws -> String?

    func updateDuration() async throws

    // MARK: - Seen marking (pure DB, no MQTT)
    func markStatusItemViewedInDB(storyId: String, userId: String) async throws
    func markStatusViewedInDB(userId: String) async throws

    // MARK: - SeenUser CRUD
    /// Returns the userId of the parent item so the caller can refresh state.
    @discardableResult
    func addSeenUser(_ seenUser: SeenUser, statusItemId: String) async throws -> String?
    func fetchSeenUsers(forStatusItemId statusItemId: String) async throws -> [SeenUser]

    // MARK: - Sync queries
    func getPendingSyncStatuses(inBackground: Bool) async throws -> [StatusItem]
    func getPendingSyncStatus(statusId: String) async throws -> StatusItem?

    /// Returns the userId of the item so the caller can refresh state.
    @discardableResult
    func updateSyncStatus(itemId: String, syncStatus: SyncStatus, errorMessage: String?) async throws -> String?
}
