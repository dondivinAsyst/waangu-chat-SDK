import Foundation
import AVFoundation
import WaanguCoreKit
import opus

// Import C wrapper for opus_encoder_ctl
// Note: The C wrapper functions are defined in OpusEncoderCWrapper.c

/// Actor-based Opus encoder for thread-safe encoding operations
public actor OpusEncoder: AudioEncoderProtocol {
    
    // MARK: - Properties
    
    private var encoder: OpaquePointer?
    private let configuration: OpusConfiguration
    private let logger: AppLogger
    private let bufferPool: AudioBufferPool
    
    // MARK: - Initialization
    
    public init(
        configuration: OpusConfiguration,
        logger: AppLogger = .shared
    ) async throws {
        self.configuration = configuration
        self.logger = logger
        self.bufferPool = AudioBufferPool()
        
        // Validate configuration
        try configuration.validate()
        
        // Initialize encoder
        try await setupEncoder()
        
        await logger.log("OpusEncoder initialized: \(configuration)", level: .info)
    }
    
    deinit {
        if let encoder = encoder {
            opus_encoder_destroy(encoder)
        }
        // Note: Cannot use async logger in deinit as it creates a retain cycle
        // The encoder cleanup is the critical part
    }
    
    // MARK: - Setup
    
    private func setupEncoder() async throws {
        var error: Int32 = 0
        
        // Create Opus encoder
        encoder = opus_encoder_create(
            Int32(configuration.sampleRate),
            Int32(configuration.channels),
            configuration.application.rawValue,
            &error
        )
        
        guard error == OPUS_OK, encoder != nil else {
            throw OpusError.encodingFailed(reason: "Failed to create encoder: \(getErrorString(error))")
        }
        
        // Configure encoder settings
        try await configureEncoder()
    }
    
    private func configureEncoder() async throws {
        guard encoder != nil else {
            throw OpusError.encoderNotInitialized
        }
        
        // Note: Swift cannot call opus_encoder_ctl (variadic C function)
        // Using Opus defaults which are already optimized for the application type
        // The encoder is created with correct application type, sample rate, and channels
        // Default settings for VOIP application:
        // - Bitrate: Auto (adapts based on complexity and bandwidth)
        // - Complexity: 10 (maximum quality)
        // - VBR: Enabled by default
        // - DTX: Disabled by default
        
        await logger.log("OpusEncoder configured with default settings", level: .info)
    }
    
    // MARK: - AudioEncoderProtocol
    
    public func encode(_ pcmData: Data, configuration: OpusConfiguration) async throws -> Data {
        guard let encoder = encoder else {
            throw OpusError.encoderNotInitialized
        }
        
        let frameSize = configuration.frameSizeInSamples
        let bytesPerSample = MemoryLayout<Int16>.size * configuration.channels
        let frameSizeInBytes = frameSize * bytesPerSample
        
        var encodedData = Data()
        var offset = 0
        
        // Process data in frames
        while offset < pcmData.count {
            let remainingBytes = pcmData.count - offset
            let currentFrameBytes = min(frameSizeInBytes, remainingBytes)
            
            // If we don't have a complete frame, pad with zeros
            var frameData: Data
            if currentFrameBytes < frameSizeInBytes {
                frameData = Data(count: frameSizeInBytes)
                frameData.replaceSubrange(0..<currentFrameBytes, with: pcmData[offset..<offset + currentFrameBytes])
            } else {
                frameData = pcmData[offset..<offset + currentFrameBytes]
            }
            
            // Encode frame
            let encodedFrame = try encodeFrame(frameData, frameSize: frameSize)
            encodedData.append(encodedFrame)
            
            offset += currentFrameBytes
        }
        
        await logger.log("Encoded \(pcmData.count) bytes to \(encodedData.count) bytes", level: .debug)
        return encodedData
    }
    
    public func encodeFile(at url: URL, configuration: OpusConfiguration) async throws -> URL {
        await logger.log("Encoding file: \(url.lastPathComponent)", level: .info)
        
        // Load PCM data
        guard let pcmData = try? Data(contentsOf: url) else {
            throw OpusError.fileNotFound(path: url.path)
        }
        
        // Encode
        let encodedData = try await encode(pcmData, configuration: configuration)
        
        // Create output URL
        let outputURL = url.deletingPathExtension().appendingPathExtension("opus")
        
        // Write encoded data
        try encodedData.write(to: outputURL, options: .atomic)
        
        await logger.log("Encoded file saved: \(outputURL.lastPathComponent)", level: .info)
        return outputURL
    }
    
    public func encodeStream(_ pcmBuffer: AVAudioPCMBuffer) async throws -> Data {
        guard let encoder = encoder else {
            throw OpusError.encoderNotInitialized
        }
        
        // Convert AVAudioPCMBuffer to Data
        guard let channelData = pcmBuffer.int16ChannelData else {
            throw OpusError.invalidAudioFormat(reason: "Buffer must be Int16 format")
        }
        
        let frameLength = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        
        // For streaming, encode the buffer directly as one frame
        // Opus expects the frame size we configured (e.g., 960 samples for 20ms at 48kHz)
        let expectedFrameSize = (configuration.sampleRate * 20) / 1000 // 20ms frame
        
        // If buffer size matches expected frame size, encode directly
        if frameLength == expectedFrameSize {
            return try encodeBufferDirect(channelData: channelData, frameLength: frameLength, channelCount: channelCount)
        }
        
        // Otherwise, fall back to the full encode method
        let dataSize = frameLength * channelCount * MemoryLayout<Int16>.size
        var pcmData = Data(count: dataSize)
        pcmData.withUnsafeMutableBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            
            if channelCount == 1 {
                // Mono
                let channel0 = channelData[0]
                for i in 0..<frameLength {
                    int16Ptr[i] = channel0[i]
                }
            } else {
                // Stereo - interleave
                let channel0 = channelData[0]
                let channel1 = channelData[1]
                for i in 0..<frameLength {
                    int16Ptr[i * 2] = channel0[i]
                    int16Ptr[i * 2 + 1] = channel1[i]
                }
            }
        }
        
        // Encode
        return try await encode(pcmData, configuration: configuration)
    }
    
    // MARK: - Private Helpers
    
    /// Encode buffer directly without data conversion (optimized for streaming)
    private func encodeBufferDirect(channelData: UnsafePointer<UnsafeMutablePointer<Int16>>, frameLength: Int, channelCount: Int) throws -> Data {
        guard let encoder = encoder else {
            throw OpusError.encoderNotInitialized
        }
        
        var outputData = Data(count: OpusConstants.maxPacketSize)
        
        let encodedSize = try outputData.withUnsafeMutableBytes { (outputBytes: UnsafeMutableRawBufferPointer) -> Int32 in
            let outputPointer = outputBytes.bindMemory(to: UInt8.self)
            
            guard let outputBase = outputPointer.baseAddress else {
                throw OpusError.encodingFailed(reason: "Failed to get output buffer pointer")
            }
            
            // For mono, use channel data directly
            // For stereo, we need to interleave (but most voice is mono)
            if channelCount == 1 {
                let result = opus_encode(
                    encoder,
                    channelData[0],
                    Int32(frameLength),
                    outputBase,
                    Int32(OpusConstants.maxPacketSize)
                )
                
                guard result > 0 else {
                    throw OpusError.encodingFailed(reason: "Encoding failed: \(getErrorString(result))")
                }
                
                return result
            } else {
                // Stereo - need to interleave
                let interleavedSize = frameLength * channelCount
                var interleavedData = [Int16](repeating: 0, count: interleavedSize)
                
                let channel0 = channelData[0]
                let channel1 = channelData[1]
                for i in 0..<frameLength {
                    interleavedData[i * 2] = channel0[i]
                    interleavedData[i * 2 + 1] = channel1[i]
                }
                
                let result = opus_encode(
                    encoder,
                    interleavedData,
                    Int32(frameLength),
                    outputBase,
                    Int32(OpusConstants.maxPacketSize)
                )
                
                guard result > 0 else {
                    throw OpusError.encodingFailed(reason: "Encoding failed: \(getErrorString(result))")
                }
                
                return result
            }
        }
        
        // Return only the encoded bytes
        return outputData.prefix(Int(encodedSize))
    }
    
    private func encodeFrame(_ frameData: Data, frameSize: Int) throws -> Data {
        guard let encoder = encoder else {
            throw OpusError.encoderNotInitialized
        }
        
        var outputData = Data(count: OpusConstants.maxPacketSize)
        
        let encodedSize = try frameData.withUnsafeBytes { (pcmBytes: UnsafeRawBufferPointer) -> Int32 in
            let pcmPointer = pcmBytes.bindMemory(to: Int16.self)
            
            return try outputData.withUnsafeMutableBytes { (outputBytes: UnsafeMutableRawBufferPointer) -> Int32 in
                let outputPointer = outputBytes.bindMemory(to: UInt8.self)
                
                guard let outputBase = outputPointer.baseAddress else {
                    throw OpusError.encodingFailed(reason: "Failed to get output buffer pointer")
                }
                
                guard let pcmBase = pcmPointer.baseAddress else {
                    throw OpusError.encodingFailed(reason: "Failed to get PCM buffer pointer")
                }
                
                let result = opus_encode(
                    encoder,
                    pcmBase,
                    Int32(frameSize),
                    outputBase,
                    Int32(OpusConstants.maxPacketSize)
                )
                
                guard result > 0 else {
                    throw OpusError.encodingFailed(reason: "Encoding failed: \(getErrorString(result))")
                }
                
                return result
            }
        }
        
        // Return only the encoded bytes
        return outputData.prefix(Int(encodedSize))
    }
    
    private func getErrorString(_ errorCode: Int32) -> String {
        switch errorCode {
        case OPUS_OK:
            return "OK"
        case OPUS_BAD_ARG:
            return "Bad argument"
        case OPUS_BUFFER_TOO_SMALL:
            return "Buffer too small"
        case OPUS_INTERNAL_ERROR:
            return "Internal error"
        case OPUS_INVALID_PACKET:
            return "Invalid packet"
        case OPUS_UNIMPLEMENTED:
            return "Unimplemented"
        case OPUS_INVALID_STATE:
            return "Invalid state"
        case OPUS_ALLOC_FAIL:
            return "Allocation failed"
        default:
            return "Unknown error (\(errorCode))"
        }
    }
}
