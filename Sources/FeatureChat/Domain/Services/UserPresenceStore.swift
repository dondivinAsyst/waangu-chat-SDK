import Foundation

/// In-memory cache of the latest presence payload per user.
final class UserPresenceStore: @unchecked Sendable {
    static let shared = UserPresenceStore()

    private let lock = NSLock()
    private var byUserId: [String: PresencePayloadDTO] = [:]

    func set(_ payload: PresencePayloadDTO) {
        lock.lock()
        defer { lock.unlock() }
        byUserId[payload.userId] = payload
    }

    func presence(for userId: String) -> PresencePayloadDTO? {
        lock.lock()
        defer { lock.unlock() }
        return byUserId[userId]
    }

    func remove(userId: String) {
        lock.lock()
        defer { lock.unlock() }
        byUserId.removeValue(forKey: userId)
    }
}
