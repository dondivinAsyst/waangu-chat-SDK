//
//  OpusAudioServiceProtocol.swift
//  CoreKit
//
//  Protocol abstraction for OpusAudioService

import Foundation

public protocol OpusAudioServiceProtocol: Sendable {
    
    // MARK: - Recording
    
    /// Start recording with real-time audio level monitoring
    func startRecording() async throws -> AsyncStream<AudioLevel>
    
    /// Pause recording
    func pauseRecording() async throws
    
    /// Resume recording
    func resumeRecording() async throws
    
    /// Stop recording and return result
    func stopRecording() async throws -> VoiceRecordingResult
    
    /// Cancel recording and cleanup
    func cancelRecording() async throws
    
    /// Check if currently recording
    var isRecording: Bool { get async }
    
    /// Get current recording duration
    var recordingDuration: TimeInterval { get async }
    
    // MARK: - Playback
    
    /// Play voice message
    func playVoiceMessage(at url: URL) async throws
    
    /// Pause playback
    func pausePlayback() async throws
    
    /// Stop playback
    func stopPlayback() async throws
    
    /// Check if currently playing
    var isPlaying: Bool { get async }
    
    /// Get current playback time
    var playbackTime: TimeInterval { get async }
    
    /// Get playback duration
    var playbackDuration: TimeInterval { get async }
    
    // MARK: - Conversion
    
    /// Convert existing audio file to Opus
    func convertToOpus(fileAt url: URL) async throws -> URL
    
    /// Convert Opus file to PCM
    func convertFromOpus(fileAt url: URL) async throws -> URL
    
    // MARK: - File Management
    
    /// Delete audio file
    func deleteAudioFile(at url: URL) async throws
    
    /// Cleanup temporary files
    func cleanupTemporaryFiles() async
}

// MARK: - Protocol Supporting Types

/// Audio level for real-time visualization
public struct AudioLevel: Sendable {
    public let rms: Float      // Root Mean Square (average level)
    public let peak: Float     // Peak level
    public let timestamp: Date
    
    public init(rms: Float, peak: Float) {
        self.rms = rms
        self.peak = peak
        self.timestamp = Date()
    }
}

/// Result of a voice recording
public struct VoiceRecordingResult: Sendable {
    public let url: URL
    public let duration: TimeInterval
    public let fileSize: Int64
    public let waveform: [Float]?
    
    public init(
        url: URL,
        duration: TimeInterval,
        fileSize: Int64,
        waveform: [Float]? = nil
    ) {
        self.url = url
        self.duration = duration
        self.fileSize = fileSize
        self.waveform = waveform
    }
}