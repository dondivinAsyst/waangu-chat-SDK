//
//  MediasoupVideoTrack.swift
//  CallMediaKit
//
//  Opaque handle handed to the feature layer so it can name a track without
//  seeing `RTCVideoTrack`.
//

import Foundation
import WaanguCoreKit
import WebRTC

/// `@unchecked Sendable`: `RTCVideoTrack` is a thread-safe native object, and
/// this wrapper only reads immutable-ish properties off it.
final class MediasoupVideoTrack: CallVideoTrackProtocol, @unchecked Sendable {

    let track: RTCVideoTrack

    init(_ track: RTCVideoTrack) {
        self.track = track
    }

    var trackId: String { track.trackId }
    var isEnabled: Bool { track.isEnabled }
}
