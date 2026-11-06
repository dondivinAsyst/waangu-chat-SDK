import Foundation

/// Tracks which conversation the user is currently viewing so sync can skip unread increments.
final class ActiveChatSessionStore: @unchecked Sendable {
    static let shared = ActiveChatSessionStore()

    private let lock = NSLock()
    private var activeConversationId: String?

    private init() {}

    func setActive(conversationId: String?) {
        lock.lock()
        defer { lock.unlock() }
        activeConversationId = conversationId
    }

    func isViewing(conversationId: String, serverId: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let active = activeConversationId, !active.isEmpty else { return false }
        if active == conversationId { return true }
        if let serverId, !serverId.isEmpty, active == serverId { return true }
        return false
    }
}
