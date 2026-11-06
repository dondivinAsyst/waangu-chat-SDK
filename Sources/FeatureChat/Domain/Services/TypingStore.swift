import Foundation
import Combine
import WaanguCoreKit

/// Who is typing right now, per conversation — the single source of truth for
/// both the chat room indicator and the discussion list row.
///
/// Typing has no "stopped" event on the wire: a peer publishes while the burst
/// lasts and simply goes quiet. So an entry is not removed by an event, it
/// *expires* — every inbound tick pushes its deadline out, and the ticker below
/// drops whatever the peer stopped refreshing. Without that, one keystroke from
/// the other side leaves "typing…" on screen forever.
///
/// One store rather than one subscription per screen: the room and the list were
/// each parsing the same topic and could disagree about the same conversation.
@MainActor
final class TypingStore: ObservableObject {

    static let shared = TypingStore()

    /// How long an entry survives without a refresh.
    ///
    /// `SendTypingUseCase` re-publishes every 3s while the burst continues, so
    /// this has to clear that interval with room for broker latency — a TTL at
    /// or near 3s makes the indicator blink between two ticks.
    static let ttl: TimeInterval = 6

    /// How often expired entries are swept. Only runs while something is typing.
    private static let pruneInterval: TimeInterval = 1

    /// Typists per conversation id, in the order they started. Empty
    /// conversations are removed rather than kept as empty arrays.
    @Published private(set) var byConversation: [String: [TypingUser]] = [:]

    private struct Entry {
        let user: TypingUser
        var expiresAt: Date
    }

    private var entries: [String: [Entry]] = [:]
    private var pruneTask: Task<Void, Never>?
    private var subscribers: [UUID: (conversationId: String, continuation: AsyncStream<[TypingUser]>.Continuation)] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - Reads

    func users(in conversationId: String) -> [TypingUser] {
        byConversation[conversationId] ?? []
    }

    /// A live feed of the typists in one conversation, starting with the
    /// current value so a room opened mid-burst shows the indicator at once.
    func stream(for conversationId: String) -> AsyncStream<[TypingUser]> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[id] = (conversationId, continuation)
            continuation.yield(users(in: conversationId))
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.subscribers.removeValue(forKey: id) }
            }
        }
    }

    // MARK: - Writes

    /// Records a typing (or recording) tick, refreshing the deadline of an
    /// entry that is already standing rather than stacking a second one.
    func set(_ user: TypingUser) {
        guard !user.conversationId.isEmpty, !user.senderId.isEmpty else { return }
        let deadline = now().addingTimeInterval(Self.ttl)
        var conversation = entries[user.conversationId] ?? []

        if let index = conversation.firstIndex(where: { $0.user.senderId == user.senderId }) {
            // Replace the payload too: the peer may have switched from typing
            // to recording a voice note, which the label has to follow.
            conversation[index] = Entry(user: user, expiresAt: deadline)
        } else {
            conversation.append(Entry(user: user, expiresAt: deadline))
        }

        entries[user.conversationId] = conversation
        publish()
        startPruningIfNeeded()
    }

    /// An explicit stop from the wire ("idle" / "offline"), which arrives from
    /// some peers and simply pre-empts the expiry.
    func clear(senderId: String, conversationId: String) {
        guard var conversation = entries[conversationId] else { return }
        conversation.removeAll { $0.user.senderId == senderId }
        entries[conversationId] = conversation.isEmpty ? nil : conversation
        publish()
    }

    /// Wipes everything. Called when the app backgrounds (the typing topic is
    /// registered `.disconnect`, so entries left behind would come back stale
    /// on resume) and on logout.
    func clearAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        publish()
    }

    // MARK: - Expiry

    private func startPruningIfNeeded() {
        guard pruneTask == nil else { return }
        // Inherits MainActor isolation from this method, so `prune()` needs no
        // hop of its own.
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pruneInterval * 1_000_000_000))
                guard let self, self.prune() else { return }
            }
        }
    }

    /// Removes expired entries. Returns whether anything is still typing —
    /// when nothing is, the ticker stops instead of spinning on an empty map.
    @discardableResult
    private func prune() -> Bool {
        let timestamp = now()
        var changed = false

        for (conversationId, conversation) in entries {
            let alive = conversation.filter { $0.expiresAt > timestamp }
            guard alive.count != conversation.count else { continue }
            changed = true
            entries[conversationId] = alive.isEmpty ? nil : alive
        }

        if changed { publish() }

        if entries.isEmpty {
            pruneTask = nil
            return false
        }
        return true
    }

    // MARK: - Publishing

    private func publish() {
        byConversation = entries.mapValues { $0.map(\.user) }
        debugLog("store: \(byConversation.mapValues(\.count))", category: "typing")
        for (_, subscriber) in subscribers {
            subscriber.continuation.yield(byConversation[subscriber.conversationId] ?? [])
        }
    }
}
