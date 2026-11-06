//
//  CallStallDetector.swift
//  FeatureChat
//
//  Spots a peer whose media has stopped arriving.
//
//  Nothing else can: when a peer loses the network their consumer stays open,
//  their track stays alive and the renderer keeps the last decoded frame on
//  screen, so no media event fires and no server event arrives — the tile simply
//  freezes while the call carries on counting. The one thing that does change is
//  the receiver's byte counter, which stops advancing.
//
//  Pure timing logic with an injected clock so it can be tested without standing
//  up a call. The wiring — polling the engine, mapping consumers to peers —
//  belongs to VoipManager.
//

import Foundation

struct CallStallDetector {

    /// How long a consumer's byte counter may sit still before its peer is
    /// treated as stalled.
    ///
    /// Long enough not to fire on ordinary jitter or a brief freeze, short
    /// enough that the user is told before they start talking to a frozen
    /// picture.
    static let stallThreshold: TimeInterval = 3

    private let threshold: TimeInterval

    /// Per consumer: the last byte count seen, and when it last went up.
    private var lastAdvance: [String: (bytes: UInt64, at: Date)] = [:]

    init(threshold: TimeInterval = CallStallDetector.stallThreshold) {
        self.threshold = threshold
    }

    /// Feeds one sample of per-consumer byte counters.
    /// - Returns: the consumers whose counter has been flat for longer than the
    ///   threshold.
    mutating func update(bytes: [String: UInt64], now: Date) -> Set<String> {
        // A consumer that is gone was closed, not stalled — forget it so a
        // reopened one starts clean rather than inheriting an old timestamp.
        lastAdvance = lastAdvance.filter { bytes.keys.contains($0.key) }

        var stalled: Set<String> = []

        for (consumerId, count) in bytes {
            guard let previous = lastAdvance[consumerId] else {
                // First sight. No history to judge against, so start the clock
                // here rather than calling it stalled.
                lastAdvance[consumerId] = (count, now)
                continue
            }

            if count > previous.bytes {
                lastAdvance[consumerId] = (count, now)
                continue
            }

            // Flat, or a counter that went backwards (consumer replaced under
            // the same id) — treat the reset as fresh rather than as a stall.
            if count < previous.bytes {
                lastAdvance[consumerId] = (count, now)
                continue
            }

            if now.timeIntervalSince(previous.at) >= threshold {
                stalled.insert(consumerId)
            }
        }

        return stalled
    }

    /// Forgets everything. Called when media stops, so the next call does not
    /// start against the last one's timestamps.
    mutating func reset() {
        lastAdvance.removeAll()
    }

    /// Which peers are stalled, given the consumers that are.
    ///
    /// A peer counts as stalled only when *every* consumer they own is stalled.
    /// One flat stream is not enough on its own: a peer who turns their camera
    /// off leaves a paused video consumer whose counter never moves again, and
    /// judging them on that alone would show "Reconnecting…" over someone who is
    /// talking perfectly well on audio.
    static func stalledOwnerKeys(
        stalledConsumers: Set<String>,
        consumerOwners: [String: String]
    ) -> Set<String> {
        var total: [String: Int] = [:]
        var stalled: [String: Int] = [:]

        for (consumerId, ownerKey) in consumerOwners {
            total[ownerKey, default: 0] += 1
            if stalledConsumers.contains(consumerId) {
                stalled[ownerKey, default: 0] += 1
            }
        }

        return Set(
            total.compactMap { ownerKey, count in
                stalled[ownerKey] == count ? ownerKey : nil
            }
        )
    }
}
