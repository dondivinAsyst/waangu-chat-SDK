import Foundation
import AVFoundation
import WaanguCoreKit

/// Actor-based audio player for Opus files
public actor OpusAudioPlayer: AudioPlayerProtocol {
    
    // MARK: - Properties
    
    private let decoder: OpusDecoder
    private let configuration: AudioPlayerConfiguration
    private let logger: AppLogger
    
    private var audioPlayer: AVAudioPlayer?
    private var currentSession: PlaybackSession?
    
    private var _isPlaying = false
    private var _currentTime: TimeInterval = 0
    private var _duration: TimeInterval = 0
    
    public var isPlaying: Bool {
        _isPlaying
    }
    
    public var currentTime: TimeInterval {
        audioPlayer?.currentTime ?? _currentTime
    }
    
    public var duration: TimeInterval {
        audioPlayer?.duration ?? _duration
    }
    
    // MARK: - Initialization
    
    public init(
        configuration: AudioPlayerConfiguration = .default,
        opusConfiguration: OpusConfiguration = .voiceMessage,
        logger: AppLogger = .shared
    ) async throws {
        self.configuration = configuration
        self.logger = logger
        self.decoder = try await OpusDecoder(configuration: opusConfiguration, logger: logger)
    }
    
    // MARK: - AudioPlayerProtocol
    
    public func play(url: URL) async throws {
        await logger.log("Playing audio: \(url.lastPathComponent)", level: .info)
        
        // Stop current playback if any
        if _isPlaying {
            try await stop()
        }
        
        // Setup audio session
        try await setupAudioSession()
        
        // Check if file is Opus format
        let fileURL: URL
        if url.pathExtension.lowercased() == "opus" {
            // Decode Opus to temporary PCM file
            fileURL = try await decodeOpusToTemporary(url: url)
        } else {
            fileURL = url
        }
        
        // Create audio player
        audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
        audioPlayer?.volume = configuration.volume
        audioPlayer?.rate = configuration.playbackRate
        audioPlayer?.prepareToPlay()
        
        // Start playback
        let success = audioPlayer?.play() ?? false
        guard success else {
            throw OpusError.playbackFailed(reason: "Failed to start playback")
        }
        
        _isPlaying = true
        _duration = audioPlayer?.duration ?? 0
        
        // Create session
        currentSession = PlaybackSession(
            configuration: configuration,
            audioURL: url,
            duration: _duration
        )
        
        await logger.log("Playback started: \(_duration)s", level: .info)
    }
    
    public func pause() async throws {
        guard _isPlaying else {
            await logger.log("Not playing", level: .warning)
            return
        }
        
        audioPlayer?.pause()
        _isPlaying = false
        _currentTime = audioPlayer?.currentTime ?? 0
        
        await logger.log("Playback paused at \(_currentTime)s", level: .info)
    }
    
    public func stop() async throws {
        audioPlayer?.stop()
        audioPlayer = nil
        _isPlaying = false
        _currentTime = 0
        currentSession = nil
        
        // Deactivate audio session
        try await deactivateAudioSession()
        
        await logger.log("Playback stopped", level: .info)
    }
    
    public func seek(to time: TimeInterval) async throws {
        guard let player = audioPlayer else {
            throw OpusError.playbackFailed(reason: "No active playback")
        }
        
        let seekTime = max(0, min(time, player.duration))
        player.currentTime = seekTime
        _currentTime = seekTime
        
        await logger.log("Seeked to \(seekTime)", level: .info)
    }
    
    // MARK: - Private Helpers
    
    private func setupAudioSession() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            await logger.log("Audio session configured for playback", level: .info)
        } catch {
            throw OpusError.audioSessionError(reason: error.localizedDescription)
        }
    }
    
    private func deactivateAudioSession() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            await logger.log("Audio session deactivated", level: .info)
        } catch {
            throw OpusError.audioSessionError(reason: error.localizedDescription)
        }
    }
    
    private func decodeOpusToTemporary(url: URL) async throws -> URL {
        await logger.log("Decoding Opus file for playback", level: .info)
        
        // Decode Opus to PCM
        let pcmURL = try await decoder.decodeFile(at: url)
        
        // Convert PCM to WAV for AVAudioPlayer
        let wavURL = pcmURL.deletingPathExtension().appendingPathExtension("wav")
        try await convertPCMToWAV(pcmURL: pcmURL, wavURL: wavURL)
        
        return wavURL
    }
    
    private func convertPCMToWAV(pcmURL: URL, wavURL: URL) async throws {
        // Simple WAV header creation
        let pcmData = try Data(contentsOf: pcmURL)
        let wavData = createWAVData(from: pcmData, sampleRate: 16000, channels: 1)
        try wavData.write(to: wavURL)
    }
    
    private func createWAVData(from pcmData: Data, sampleRate: Int, channels: Int) -> Data {
        var wavData = Data()
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        let fileSize = UInt32(36 + pcmData.count)
        wavData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        let fmtChunkSize = UInt32(16)
        wavData.append(contentsOf: withUnsafeBytes(of: fmtChunkSize.littleEndian) { Data($0) })
        let audioFormat = UInt16(1) // PCM
        wavData.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        let numChannels = UInt16(channels)
        wavData.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        let sampleRateValue = UInt32(sampleRate)
        wavData.append(contentsOf: withUnsafeBytes(of: sampleRateValue.littleEndian) { Data($0) })
        let byteRate = UInt32(sampleRate * channels * 2) // 16-bit
        wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        let blockAlign = UInt16(channels * 2)
        wavData.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        let bitsPerSample = UInt16(16)
        wavData.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        let dataSize = UInt32(pcmData.count)
        wavData.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(pcmData)
        
        return wavData
    }
}
