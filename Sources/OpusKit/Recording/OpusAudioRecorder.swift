import Foundation
import AVFoundation
import WaanguCoreKit

/// Actor-based audio recorder with Opus encoding and real-time audio level monitoring
public actor OpusAudioRecorder: AudioRecorderProtocol {
    
    // MARK: - Properties
    
    private let encoder: OpusEncoder
    private var syncEncoder: OpusSyncEncoder? // Synchronous encoder for real-time recording
    private let configuration: AudioRecorderConfiguration
    private let logger: AppLogger
    private let fileManager: AudioFileManager
    
    private var audioEngine: AVAudioEngine?
    private var recordingURL: URL?
    private var oggWriter: OggOpusWriter?
    private var recordingStartTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?
    
    private var audioLevelContinuation: AsyncStream<Float>.Continuation?
    
    // Synchronous processing queue for audio buffers
    private let processingQueue = DispatchQueue(label: "com.opuskit.audioprocessing", qos: .userInitiated)
    
    // Buffer statistics
    private var buffersReceived: Int = 0
    private var buffersProcessed: Int = 0
    
    // Cached duration after recording stops
    private var cachedDuration: TimeInterval = 0
    
    // State
    private var _isRecording = false
    private var _isPaused = false
    
    public var isRecording: Bool {
        _isRecording
    }
    
    public var recordingDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        let elapsed = Date().timeIntervalSince(startTime) - pausedDuration
        return max(0, elapsed)
    }
    
    /// Get actual audio duration based on encoded samples (not wall-clock time)
    public var actualRecordingDuration: TimeInterval {
        // If recording is stopped, return cached duration
        if !_isRecording && cachedDuration > 0 {
            return cachedDuration
        }
        // If still recording, get from writer
        guard let writer = oggWriter else { return 0 }
        return writer.getActualDuration()
    }
    
    // MARK: - Initialization
    
    public init(
        configuration: AudioRecorderConfiguration,
        fileManager: AudioFileManager,
        logger: AppLogger = .shared
    ) async throws {
        self.configuration = configuration
        self.fileManager = fileManager
        self.logger = logger
        
        // Create encoder
        self.encoder = try await OpusEncoder(
            configuration: configuration.opusConfiguration,
            logger: logger
        )
        
        await logger.log("OpusAudioRecorder initialized", level: .info)
    }
    
    // MARK: - AudioRecorderProtocol
    
    public func startRecording(configuration: AudioRecorderConfiguration) async throws {
        guard !_isRecording else {
            await logger.log("Already recording", level: .warning)
            return
        }
        
        // Setup audio session
        try setupAudioSession()
        
        // Create recording URL
        if let configURL = configuration.outputURL {
            recordingURL = configURL
        } else {
            recordingURL = await fileManager.createTemporaryURL(format: .opus)
        }
        
        // Initialize Ogg Opus writer
        oggWriter = try OggOpusWriter(
            sampleRate: configuration.opusConfiguration.sampleRate,
            channels: configuration.opusConfiguration.channels
        )
        
        // Create synchronous encoder for real-time recording
        syncEncoder = try OpusSyncEncoder(configuration: configuration.opusConfiguration)
        
        // Reset state
        recordingStartTime = Date()
        pausedDuration = 0
        pauseStartTime = nil
        _isPaused = false
        buffersReceived = 0
        buffersProcessed = 0
        cachedDuration = 0
        
        // Setup audio engine
        try setupAudioEngine()
        
        // Start engine
        try audioEngine?.start()
        
        _isRecording = true
        await logger.log("Recording started: \(recordingURL?.lastPathComponent ?? "unknown")", level: .info)
    }
    
    public func stopRecording() async throws -> URL {
        guard _isRecording else {
            throw OpusError.recordingFailed(reason: "Not recording")
        }
        
        // Stop engine
        audioEngine?.stop()
        audioEngine = nil
        
        // Log buffer statistics
        await logger.log("📊 Recording stats: received=\(buffersReceived), processed=\(buffersProcessed), dropped=\(buffersReceived - buffersProcessed)", level: .info)
        
        // Finalize recording
        guard let url = recordingURL else {
            throw OpusError.recordingFailed(reason: "No recording URL")
        }
        
        guard let writer = oggWriter else {
            throw OpusError.recordingFailed(reason: "Ogg writer not initialized")
        }
        
        // Get actual duration BEFORE finalizing (writer will be nil after)
        let actualDuration = writer.getActualDuration()
        
        // Finalize Ogg stream and get complete file data
        let oggData = try writer.finalize()
        
        // Save Ogg Opus file
        try await fileManager.save(oggData, to: url)
        
        // Store duration for later retrieval
        cachedDuration = actualDuration
        
        // Cleanup
        _isRecording = false
        _isPaused = false
        oggWriter = nil
        syncEncoder = nil
        audioLevelContinuation?.finish()
        audioLevelContinuation = nil
        
        await logger.log("Recording stopped: \(actualDuration)s (actual), \(oggData.count) bytes", level: .info)
        
        // Deactivate audio session
        try deactivateAudioSession()
        
        return url
    }
    
    public func pauseRecording() async throws {
        guard _isRecording && !_isPaused else {
            await logger.log("Cannot pause: not recording or already paused", level: .warning)
            return
        }
        
        audioEngine?.pause()
        _isPaused = true
        pauseStartTime = Date()
        
        await logger.log("Recording paused", level: .info)
    }
    
    public func resumeRecording() async throws {
        guard _isRecording && _isPaused else {
            await logger.log("Cannot resume: not recording or not paused", level: .warning)
            return
        }
        
        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
        }
        
        try audioEngine?.start()
        _isPaused = false
        pauseStartTime = nil
        
        await logger.log("Recording resumed", level: .info)
    }
    
    public func cancelRecording() async throws {
        guard _isRecording else {
            await logger.log("Not recording", level: .warning)
            return
        }
        
        // Stop engine
        audioEngine?.stop()
        audioEngine = nil
        
        // Delete recording file if exists
        if let url = recordingURL {
            try? await fileManager.delete(at: url)
        }
        
        // Cleanup
        _isRecording = false
        _isPaused = false
        oggWriter = nil
        syncEncoder = nil
        audioLevelContinuation?.finish()
        audioLevelContinuation = nil
        
        await logger.log("Recording cancelled", level: .info)
        
        // Deactivate audio session
        try deactivateAudioSession()
    }
    
    // MARK: - Audio Level Stream
    
    /// Get real-time audio level stream
    public func audioLevelStream() -> AsyncStream<Float> {
        AsyncStream { continuation in
            self.audioLevelContinuation = continuation
        }
    }
    
    // MARK: - Private Setup
    
    private func setupAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            switch configuration.audioSessionCategory {
            case .playAndRecord:
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            case .record:
                try audioSession.setCategory(.record, mode: .default)
            case .playback:
                try audioSession.setCategory(.playback, mode: .default)
            }
            
            try audioSession.setActive(true)
            Task {
                await logger.log("Audio session configured", level: .info)
            }
        } catch {
            throw OpusError.audioSessionError(reason: error.localizedDescription)
        }
    }
    
    private func deactivateAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            Task {
                await logger.log("Audio session deactivated", level: .info)
            }
        } catch {
            throw OpusError.audioSessionError(reason: error.localizedDescription)
        }
    }
    
    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create desired format for Opus
        guard let recordingFormat = AVAudioFormat.opusPCMFormat(
            sampleRate: Double(configuration.opusConfiguration.sampleRate),
            channels: AVAudioChannelCount(configuration.opusConfiguration.channels)
        ) else {
            throw OpusError.invalidAudioFormat(reason: "Failed to create recording format")
        }
        
        // Install tap on input node with SYNCHRONOUS processing
        let bufferSize = AVAudioFrameCount(1024)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Process synchronously on dedicated queue to prevent buffer drops
            self.processingQueue.sync {
                self.processAudioBufferSync(buffer, format: recordingFormat)
            }
        }
        
        // Prepare engine
        engine.prepare()
        
        self.audioEngine = engine
        Task {
            await logger.log("Audio engine configured with synchronous processing", level: .info)
        }
    }
    
    
    /// Synchronous audio buffer processing (called from audio thread)
    /// This method MUST be fast and synchronous to prevent buffer drops
    private func processAudioBufferSync(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        // Increment received counter
        buffersReceived += 1
        
        // Quick check if we should process
        guard _isRecording && !_isPaused else { return }
        
        do {
            // Convert buffer to target format if needed
            let convertedBuffer = try convertBuffer(buffer, to: format)
            
            // Calculate audio level
            if configuration.enableLevelMonitoring {
                let level = calculateAudioLevel(from: convertedBuffer)
                
                // Debug: Log first few levels to see what we're getting
                if buffersProcessed < 5 {
                    Task { [weak self] in
                        await self?.logger.log("🎤 Audio level: \(String(format: "%.3f", level)), format: \(convertedBuffer.format), frameLength: \(convertedBuffer.frameLength), hasFloatData: \(convertedBuffer.floatChannelData != nil), hasInt16Data: \(convertedBuffer.int16ChannelData != nil)", level: .info)
                    }
                }
                
                // Send level update asynchronously (non-blocking)
                Task { [weak self] in
                    await self?.sendAudioLevel(level)
                }
            }
            
            // Encode to Opus SYNCHRONOUSLY using the sync encoder
            guard let syncEncoder = syncEncoder else {
                Task { [weak self] in
                    await self?.logger.log("Sync encoder not initialized", level: .error)
                }
                return
            }
            
            let encodedData = try syncEncoder.encodeBuffer(convertedBuffer)
            
            // Write Opus packet to Ogg container
            guard let writer = oggWriter else {
                Task { [weak self] in
                    await self?.logger.log("Ogg writer not initialized", level: .error)
                }
                return
            }
            
            // Calculate samples in this frame
            let samples = Int(convertedBuffer.frameLength)
            
            try writer.writePacket(encodedData, samples: samples)
            
            // Increment processed counter
            buffersProcessed += 1
            
        } catch {
            Task { [weak self] in
                await self?.logger.log("Failed to process audio buffer: \(error.localizedDescription)", level: .error)
            }
        }
    }
    
    /// Send audio level update (async, non-blocking)
    private func sendAudioLevel(_ level: Float) async {
        if audioLevelContinuation != nil {
            audioLevelContinuation?.yield(level)
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) async {
        guard _isRecording && !_isPaused else { return }
        
        do {
            // Convert buffer to target format if needed
            let convertedBuffer = try convertBuffer(buffer, to: format)
            
            // Calculate audio level
            if configuration.enableLevelMonitoring {
                let level = calculateAudioLevel(from: convertedBuffer)
                audioLevelContinuation?.yield(level)
            }
            
            // Encode to Opus
            let encodedData = try await encoder.encodeStream(convertedBuffer)
            
            // Write Opus packet to Ogg container
            guard let writer = oggWriter else {
                throw OpusError.recordingFailed(reason: "Ogg writer not initialized")
            }
            
            // Calculate samples in this frame
            let samples = Int(convertedBuffer.frameLength)
            
            try writer.writePacket(encodedData, samples: samples)
            
        } catch {
            await logger.log("Failed to process audio buffer: \(error.localizedDescription)", level: .error)
        }
    }
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        // If formats match, return original buffer
        if buffer.format == format {
            return buffer
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            throw OpusError.conversionFailed(reason: "Failed to create audio converter")
        }
        
        // Calculate output frame capacity
        let ratio = format.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: outputFrameCapacity
        ) else {
            throw OpusError.bufferAllocationFailed
        }
        
        // Convert
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            throw OpusError.conversionFailed(reason: error.localizedDescription)
        }
        
        return outputBuffer
    }
    
    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            // Buffer doesn't have float channel data - might be in Int16 format
            // Try to get Int16 data and convert
            if let int16Data = buffer.int16ChannelData {
                return calculateAudioLevelFromInt16(buffer: buffer, channelData: int16Data)
            }
            return 0.0
        }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        guard frameLength > 0 else { return 0.0 }
        
        var sum: Float = 0.0
        var count = 0
        
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sum += sample * sample
                count += 1
            }
        }
        
        guard count > 0 else { return 0.0 }
        
        // Calculate RMS (Root Mean Square)
        let rms = sqrt(sum / Float(count))
        
        // Normalize to 0.0-1.0 range (typical speech is around 0.1 RMS)
        let normalized = min(1.0, max(0.0, rms * 10.0))
        
        return normalized
    }
    
    private func calculateAudioLevelFromInt16(buffer: AVAudioPCMBuffer, channelData: UnsafePointer<UnsafeMutablePointer<Int16>>) -> Float {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        guard frameLength > 0 else { return 0.0 }
        
        var sum: Float = 0.0
        var count = 0
        
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                // Convert Int16 (-32768 to 32767) to Float (-1.0 to 1.0)
                let sample = Float(samples[frame]) / 32768.0
                sum += sample * sample
                count += 1
            }
        }
        
        guard count > 0 else { return 0.0 }
        
        // Calculate RMS (Root Mean Square)
        let rms = sqrt(sum / Float(count))
        
        // Normalize to 0.0-1.0 range
        let normalized = min(1.0, max(0.0, rms * 10.0))
        
        return normalized
    }
}
