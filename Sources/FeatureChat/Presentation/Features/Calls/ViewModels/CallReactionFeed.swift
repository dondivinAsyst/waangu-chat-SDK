import Foundation

/// One emoji somebody sent, alive only long enough to animate.
struct CallReaction: Identifiable, Equatable {
    let id: UUID
    let peerId: String
    let emoji: String
    let createdAt: Date

    init(id: UUID = UUID(), peerId: String, emoji: String, createdAt: Date) {
        self.id = id
        self.peerId = peerId
        self.emoji = emoji
        self.createdAt = createdAt
    }
}

/// The reactions currently on screen.
///
/// Nothing here reaches a repository: CALL-INTEGRATION V3 §16.2 is explicit that
/// reactions are ephemeral and must not be written to chat history. That is the
/// one rule this type exists to keep.
struct CallReactionFeed: Equatable {

    /// §16.2 asks for 2–3s on the tile.
    static let ttl: TimeInterval = 2.5

    /// The exact set the contract allows (§16.2 step 1).
    static let palette = ["👍", "❤️", "😂", "😮", "😢", "👏", "🎉", "🔥"]

    private(set) var items: [CallReaction] = []

    /// - Returns: the new reaction's id, so the caller can schedule its prune.
    @discardableResult
    mutating func add(peerId: String, emoji: String, at date: Date) -> UUID {
        let reaction = CallReaction(peerId: peerId, emoji: emoji, createdAt: date)
        items.append(reaction)
        return reaction.id
    }

    mutating func prune(now: Date, ttl: TimeInterval = CallReactionFeed.ttl) {
        items.removeAll { now.timeIntervalSince($0.createdAt) >= ttl }
    }

    mutating func removeAll() {
        items.removeAll()
    }
}
