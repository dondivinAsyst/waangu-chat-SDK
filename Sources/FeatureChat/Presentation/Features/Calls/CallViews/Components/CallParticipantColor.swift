//
//  CallParticipantColor.swift
//  FeatureChat
//
//  A colour per person on a call, so a tile can be recognised at a glance.
//

import SwiftUI

/// Gives every participant a colour of their own.
///
/// Derived from the peer key rather than assigned at random. Random colours
/// would be re-rolled on every render, letting a tile change colour mid-call,
/// and two people could land close enough together to be indistinguishable.
/// Hashing the key instead means one person keeps one colour for the whole
/// call — and, because every device runs the same function over the same ids,
/// the same colour on everybody's screen.
enum CallParticipantColor {

    /// Hues spaced far enough apart to stay distinct on a dark call background,
    /// avoiding the red reserved for "end call" and the green used for accept.
    private static let hues: [Double] = [
        204,  // blue
        280,  // violet
        32,   // amber
        170,  // teal
        320,  // pink
        96,   // lime
        250,  // indigo
        16    // orange
    ]

    /// The colour for a participant key.
    ///
    /// `key` is expected to be a normalised participant key, so the same person
    /// resolves identically no matter which of their ids the caller holds.
    static func color(forKey key: String) -> Color {
        let hue = hues[bucket(for: key)] / 360
        return Color(hue: hue, saturation: 0.72, brightness: 0.98)
    }

    /// Stable index into `hues`.
    ///
    /// FNV-1a rather than `String.hashValue`: Swift seeds its hasher per process,
    /// so `hashValue` would give the same person a different colour on every
    /// launch — and a different colour on each participant's device.
    private static func bucket(for key: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(hues.count))
    }
}
