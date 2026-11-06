//
//  FrameRateLimiter.swift
//  ScreenShareTransport
//
//  Admits at most `framesPerSecond` frames. ReplayKit pushes at display rate;
//  everything above this is uplink and battery spent on a screen that barely
//  changes between frames.
//

import Foundation

public struct FrameRateLimiter {

    private let intervalNanos: UInt64
    private var lastSentNanos: UInt64?

    public init(framesPerSecond: Int = 15) {
        precondition(framesPerSecond > 0, "framesPerSecond must be positive")
        self.intervalNanos = UInt64(1_000_000_000 / framesPerSecond)
    }

    public mutating func shouldSend(at timestampNanos: UInt64) -> Bool {
        guard let last = lastSentNanos else {
            lastSentNanos = timestampNanos
            return true
        }

        // A restarted broadcast reuses the clock and can hand back a smaller
        // timestamp. Treating that as "too soon" would wedge the stream shut,
        // so resynchronise instead.
        guard timestampNanos >= last else {
            lastSentNanos = timestampNanos
            return true
        }

        guard timestampNanos - last >= intervalNanos else { return false }
        lastSentNanos = timestampNanos
        return true
    }
}
