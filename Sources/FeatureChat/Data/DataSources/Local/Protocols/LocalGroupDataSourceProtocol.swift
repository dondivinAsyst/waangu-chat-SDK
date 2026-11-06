import Foundation

public protocol LocalGroupDataSourceProtocol {
    func save(_ group: GroupChat) async throws
    func fetch(id: String) async throws -> GroupChat?
    func fetchByLocalId(_ localId: String) async throws -> GroupChat?
    func fetchByServerId(_ serverId: String) async throws -> GroupChat?
    func fetchAll() async throws -> [GroupChat]
    func fetchActive() async throws -> [GroupChat]
    func fetchPending() async throws -> [GroupChat]
    func update(_ group: GroupChat) async throws
    func delete(id: String) async throws

    func activateGroup(localId: String, serverId: String) async throws
    func updateServerId(localId: String, serverId: String) async throws
    func markSyncFailed(localId: String, error: String) async throws
    func markSyncSuccess(localId: String) async throws
    func markSyncing(localId: String) async throws
    func incrementRetryCount(localId: String) async throws

    func addMember(_ member: GroupMember, to groupId: String) async throws
    func removeMember(userId: String, from groupId: String) async throws
    func deactivateMember(userId: String, from groupId: String) async throws
    func updateMember(_ member: GroupMember, in groupId: String) async throws
}
