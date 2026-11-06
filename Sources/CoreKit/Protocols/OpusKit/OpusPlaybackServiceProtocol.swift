//
//  OpusPlaybackServiceProtocol.swift
//  CoreKit
//
//  Protocol abstraction for OpusPlaybackService

import Foundation

public protocol OpusPlaybackServiceProtocol: Sendable {
    
    /// Decode Opus file to WAV for playback with AVAudioPlayer
    /// Returns URL of decoded WAV file (cached)
    func decodeForPlayback(opusURL: URL) async throws -> URL
    
    /// Clear decoded audio cache
    func clearCache() async
}