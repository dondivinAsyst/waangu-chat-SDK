import Foundation

protocol LocalContactSyncStateDataSourceProtocol {
    func fetchAllSyncStates() async throws -> [ContactSyncState]
    func fetchSyncState(contactId: String) async throws -> ContactSyncState?
    func saveSyncState(_ state: ContactSyncState) async throws
    func saveSyncStates(_ states: [ContactSyncState]) async throws
    func deleteSyncState(contactId: String) async throws
    func deleteSyncStates(contactIds: [String]) async throws
    func deleteAllSyncStates() async throws
}
