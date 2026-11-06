import Foundation
import Combine
import WaanguCoreKit

/// View model for voice recording with real-time audio level monitoring
@MainActor
public final class VoiceRecordingViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var isRecording = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var isLocked = false
    @Published public private(set) var elapsedTime: TimeInterval = 0
    @Published public private(set) var audioLevels: [Float] = Array(repeating: 0, count: 60) // 60 bars for full width
    @Published public private(set) var currentAudioLevel: Float = 0
    @Published public private(set) var recordingState: RecordingState = .idle
    
    // MARK: - Dependencies
    
    private let opusAudioService: any OpusAudioServiceProtocol
    private let logger: any AppLoggerProtocol
    
    // MARK: - State
    
    private var recordingTask: Task<Void, Never>?
    private var audioLevelTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var startTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?
    
    // MARK: - Initialization
    
    public init(
        opusAudioService: any OpusAudioServiceProtocol,
        logger: any AppLoggerProtocol
    ) {
        self.opusAudioService = opusAudioService
        self.logger = logger
    }
    
    // MARK: - Recording Control
    
    public func startRecording() async {
        guard !isRecording else { return }
        
        do {
            // Start recording and get audio level stream
            let audioLevelStream = try await opusAudioService.startRecording()
            
            isRecording = true
            recordingState = .recording
            startTime = Date()
            pausedDuration = 0
            
            // Start timer
            startTimer()
            
            // Monitor audio levels
            startAudioLevelMonitoring(stream: audioLevelStream)
            
            await logger.log("Voice recording started", level: .info)
        } catch {
            await logger.log("Failed to start recording: \(error.localizedDescription)", level: .error)
            // TODO: Show error to user
        }
    }
    
    public func pauseRecording() async {
        guard isRecording && !isPaused else { return }
        
        do {
            try await opusAudioService.pauseRecording()
            isPaused = true
            recordingState = .paused
            pauseStartTime = Date()
            await logger.log("Voice recording paused", level: .info)
        } catch {
            await logger.log("Failed to pause recording: \(error.localizedDescription)", level: .error)
        }
    }
    
    public func resumeRecording() async {
        guard isRecording && isPaused else { return }
        
        do {
            try await opusAudioService.resumeRecording()
            
            if let pauseStart = pauseStartTime {
                pausedDuration += Date().timeIntervalSince(pauseStart)
            }
            
            isPaused = false
            recordingState = isLocked ? .locked : .recording
            pauseStartTime = nil
            await logger.log("Voice recording resumed", level: .info)
        } catch {
            await logger.log("Failed to resume recording: \(error.localizedDescription)", level: .error)
        }
    }
    
    public func stopRecording() async -> VoiceRecordingResult? {
        guard isRecording else { return nil }
        
        // Cancel timer immediately before stopping recording
        timerTask?.cancel()
        timerTask = nil
        
        do {
            let result = try await opusAudioService.stopRecording()
            cleanup()
            await logger.log("Voice recording stopped: \(result.duration)s, \(result.fileSize) bytes", level: .info)
            return result
        } catch {
            await logger.log("Failed to stop recording: \(error.localizedDescription)", level: .error)
            cleanup()
            return nil
        }
    }
    
    public func cancelRecording() async {
        guard isRecording else { return }
        
        do {
            try await opusAudioService.cancelRecording()
            cleanup()
            await logger.log("Voice recording cancelled", level: .info)
        } catch {
            await logger.log("Failed to cancel recording: \(error.localizedDescription)", level: .error)
            cleanup()
        }
    }
    
    public func lockRecording() async {
        isLocked = true
        recordingState = .locked
        await logger.log("Voice recording locked", level: .info)
    }
    
    // MARK: - Private Helpers
    
    private func startTimer() {
        // Capture start time once to prevent resets
        guard let recordingStartTime = startTime else { return }
        
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                
                guard let self = self else { break }
                
                // Calculate elapsed time from captured start time
                let now = Date()
                var elapsed = now.timeIntervalSince(recordingStartTime)
                
                // Subtract paused duration
                elapsed -= self.pausedDuration
                
                // If currently paused, also subtract time since pause started
                if self.isPaused, let pauseStart = self.pauseStartTime {
                    elapsed -= now.timeIntervalSince(pauseStart)
                }
                
                // Ensure non-negative
                self.elapsedTime = max(0, elapsed)
            }
        }
    }
    
    private func startAudioLevelMonitoring(stream: AsyncStream<AudioLevel>) {
        audioLevelTask = Task { @MainActor [weak self] in
            var levelCount = 0
            for await level in stream {
                guard let self = self else { return }
                
                levelCount += 1
                if levelCount % 10 == 0 {
                    debugLog("🎵 VoiceRecordingViewModel: Received \(levelCount) audio levels, latest RMS: \(String(format: "%.3f", level.rms))")
                }
                
                // Update current level
                self.currentAudioLevel = level.rms
                
                // Update waveform (shift and add new level) - WhatsApp style: right to left
                var newLevels = self.audioLevels
                newLevels.removeFirst() // Remove leftmost (oldest)
                newLevels.append(level.rms) // Add to right (newest)
                
                // Ensure exactly 60 elements
                if newLevels.count < 60 {
                    newLevels.append(contentsOf: Array(repeating: 0, count: 60 - newLevels.count))
                } else if newLevels.count > 60 {
                    newLevels = Array(newLevels.suffix(60))
                }
                debugLog("🎵 VoiceRecordingViewModel: Audio level stream ended after \(levelCount) levels and self \(newLevels) 1111111")
                self.audioLevels = newLevels
            }
            debugLog("🎵 VoiceRecordingViewModel: Audio level stream ended after \(levelCount) levels and self \(audioLevels)")
        }
    }
    
    @MainActor
    private func cleanup() {
        isRecording = false
        isPaused = false
        isLocked = false
        elapsedTime = 0
        audioLevels = Array(repeating: 0, count: 60) // Reset to 60 bars
        currentAudioLevel = 0
        recordingState = .idle
        startTime = nil
        pausedDuration = 0
        pauseStartTime = nil
        
        timerTask?.cancel()
        audioLevelTask?.cancel()
        recordingTask?.cancel()
    }
    
    deinit {
        // Cancel tasks synchronously
        timerTask?.cancel()
        audioLevelTask?.cancel()
        recordingTask?.cancel()
    }
}

// MARK: - Recording State

public enum RecordingState: Sendable {
    case idle
    case recording
    case locked
    case paused
}
