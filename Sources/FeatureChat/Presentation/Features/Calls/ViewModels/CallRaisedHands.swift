import Foundation

/// Who has asked to speak, in the order the server puts them.
///
/// A value type rather than state spread across `VoipManager`: the ordering
/// rules are the whole feature, and they are worth testing without standing up
/// a call.
struct CallRaisedHands: Equatable {

    private(set) var queue: [String] = []

    /// Adds a hand, ignoring one already up.
    ///
    /// `HAND_RAISED` and `REQUEST_TO_SPEAK` describe the same act and both
    /// arrive, so a plain append would give one person two places in the queue.
    mutating func raise(_ peerId: String) {
        guard !peerId.isEmpty, !queue.contains(peerId) else { return }
        queue.append(peerId)
    }

    mutating func lower(_ peerId: String) {
        queue.removeAll { $0 == peerId }
    }

    /// Takes the server's ordering when it sends one.
    ///
    /// Not every event carries `speakingQueue`, and nil means "no opinion" —
    /// clearing on it would empty the list every time a bare event arrived.
    mutating func apply(serverQueue: [String]?) {
        guard let serverQueue else { return }
        queue = serverQueue.filter { !$0.isEmpty }
    }

    mutating func removeAll() {
        queue.removeAll()
    }

    func contains(_ peerId: String) -> Bool {
        queue.contains(peerId)
    }
}
