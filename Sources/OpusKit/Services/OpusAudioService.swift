import Foundation
import AVFoundation
import WaanguCoreKit
import WaanguStorageKit

/// High-level audio service for recording and playback with Opus codec
public actor OpusAudioService: OpusAudioServiceProtocol {
    
    // MARK: - Properties
    
    private let encoder: OpusEncoder
    private let decoder: OpusDecoder
    private var recorder: OpusAudioRecorder?
    private var player: OpusAudioPlayer?
    private let fileManager: AudioFileManager
    private let logger: AppLogger
    
    private var currentRecordingSession: RecordingSession?
    private var currentPlaybackSession: PlaybackSession?
    
    // MARK: - Initialization
    
    public init(
        configuration: OpusConfiguration = .voiceMessage,
        logger: AppLogger = .shared
    ) async throws {
        self.logger = logger
        self.fileManager = AudioFileManager(logger: logger)
        
        // Initialize encoder and decoder
        self.encoder = try await OpusEncoder(configuration: configuration, logger: logger)
        self.decoder = try await OpusDecoder(configuration: configuration, logger: logger)
        
        await logger.log("OpusAudioService initialized", level: .info)
    }
    
    // MARK: - Recording
    
    /// Start recording with real-time audio level monitoring
    /// - Returns: AsyncStream of audio levels for UI visualization
    public func startRecording() async throws -> AsyncStream<AudioLevel> {
        return try await startRecording(configuration: .voiceMessage)
    }
    
    /// Start recording with real-time audio level monitoring
    /// - Returns: AsyncStream of audio levels for UI visualization
    public func startRecording(
        configuration: AudioRecorderConfiguration = .voiceMessage
    ) async throws -> AsyncStream<AudioLevel> {
        guard recorder == nil else {
            throw OpusError.recordingFailed(reason: "Already recording")
        }
        
        // Create recorder
        let newRecorder = try await OpusAudioRecorder(
            configuration: configuration,
            fileManager: fileManager,
            logger: logger
        )
        
        // Start recording
        try await newRecorder.startRecording(configuration: configuration)
        
        // Create session
        let outputURL: URL
        if let configURL = configuration.outputURL {
            outputURL = configURL
        } else {
            outputURL = await fileManager.createTemporaryURL(format: .opus)
        }
        currentRecordingSession = RecordingSession(
            configuration: configuration,
            outputURL: outputURL
        )
        
        self.recorder = newRecorder
        
        // Map audio level stream
        let levelStream = await newRecorder.audioLevelStream()
        return AsyncStream { continuation in
            Task {
                for await level in levelStream {
                    let audioLevel = AudioLevel(rms: level, peak: level * 1.2)
                    continuation.yield(audioLevel)
                }
                continuation.finish()
            }
        }
    }
    
    /// Pause recording
    public func pauseRecording() async throws {
        guard let recorder = recorder else {
            throw OpusError.recordingFailed(reason: "Not recording")
        }
        
        try await recorder.pauseRecording()
        await logger.log("Recording paused", level: .info)
    }
    
    /// Resume recording
    public func resumeRecording() async throws {
        guard let recorder = recorder else {
            throw OpusError.recordingFailed(reason: "Not recording")
        }
        
        try await recorder.resumeRecording()
        await logger.log("Recording resumed", level: .info)
    }
    
    /// Stop recording and return result
    public func stopRecording() async throws -> VoiceRecordingResult {
        guard let recorder = recorder else {
            throw OpusError.recordingFailed(reason: "Not recording")
        }
        
        let url = try await recorder.stopRecording()
        // Use actual audio duration (based on samples) not wall-clock time
        let duration = await recorder.actualRecordingDuration
        
        // Get file metadata
        let metadata = try await fileManager.getMetadata(for: url)
        
        // Extract waveform for visualization (async, non-blocking)
        let waveform = try? await extractWaveform(from: url)
        
        // Cleanup
        self.recorder = nil
        currentRecordingSession = nil
        
        return VoiceRecordingResult(
            url: url,
            duration: duration,
            fileSize: metadata.fileSize,
            waveform: waveform
        )
    }
    
    /// Extract waveform from audio file
    private func extractWaveform(from url: URL) async throws -> [Float] {
        // For now, return a simple waveform based on file size
        // TODO: Implement proper waveform extraction from Opus file
        let barCount = 40
        var waveform: [Float] = []
        
        // Generate a simple waveform pattern
        for i in 0..<barCount {
            let value = Float.random(in: 0.3...0.9)
            waveform.append(value)
        }
        
        return waveform
    }
    
    /// Cancel recording and cleanup
    public func cancelRecording() async throws {
        guard let recorder = recorder else {
            throw OpusError.recordingFailed(reason: "Not recording")
        }
        
        try await recorder.cancelRecording()
        
        // Cleanup
        self.recorder = nil
        currentRecordingSession = nil
        
        await logger.log("Recording cancelled", level: .info)
    }
    
    /// Check if currently recording
    public var isRecording: Bool {
        get async {
            guard let recorder = recorder else { return false }
            return await recorder.isRecording
        }
    }
    
    /// Get current recording duration
    public var recordingDuration: TimeInterval {
        get async {
            guard let recorder = recorder else { return 0 }
            return await recorder.recordingDuration
        }
    }
    
    // MARK: - Playback
    
    /// Play voice message
    public func playVoiceMessage(at url: URL) async throws {
        await logger.log("Playing voice message: \(url.lastPathComponent)", level: .info)
        
        // Create player if needed
        if player == nil {
            player = try await OpusAudioPlayer(
                configuration: .voiceMessage,
                logger: logger
            )
        }
        
        guard let player = player else {
            throw OpusError.playbackFailed(reason: "Failed to create player")
        }
        
        try await player.play(url: url)
    }
    
    /// Pause playback
    public func pausePlayback() async throws {
        guard let player = player else {
            throw OpusError.playbackFailed(reason: "No active playback")
        }
        
        try await player.pause()
    }
    
    /// Stop playback
    public func stopPlayback() async throws {
        guard let player = player else {
            throw OpusError.playbackFailed(reason: "No active playback")
        }
        
        try await player.stop()
        self.player = nil
    }
    
    /// Check if currently playing
    public var isPlaying: Bool {
        get async {
            guard let player = player else { return false }
            return await player.isPlaying
        }
    }
    
    /// Get current playback time
    public var playbackTime: TimeInterval {
        get async {
            guard let player = player else { return 0 }
            return await player.currentTime
        }
    }
    
    /// Get playback duration
    public var playbackDuration: TimeInterval {
        get async {
            guard let player = player else { return 0 }
            return await player.duration
        }
    }
    
    // MARK: - Conversion
    
    /// Convert existing audio file to Opus
    public func convertToOpus(fileAt url: URL) async throws -> URL {
        await logger.log("Converting file to Opus: \(url.lastPathComponent)", level: .info)
        return try await encoder.encodeFile(at: url, configuration: .voiceMessage)
    }
    
    /// Convert Opus file to PCM
    public func convertFromOpus(fileAt url: URL) async throws -> URL {
        await logger.log("Converting Opus file to PCM: \(url.lastPathComponent)", level: .info)
        return try await decoder.decodeFile(at: url)
    }
    
    // MARK: - File Management
    
    /// Delete audio file
    public func deleteAudioFile(at url: URL) async throws {
        try await fileManager.delete(at: url)
    }
    
    /// Cleanup temporary files
    public func cleanupTemporaryFiles() async {
        await fileManager.cleanupTemporaryFiles()
    }
}
