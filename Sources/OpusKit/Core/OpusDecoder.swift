import Foundation
import AVFoundation
import WaanguCoreKit
import opus

/// Actor-based Opus decoder for thread-safe decoding operations
public actor OpusDecoder: AudioDecoderProtocol {
    
    // MARK: - Properties
    
    private var decoder: OpaquePointer?
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
        
        // Initialize decoder
        try await setupDecoder()
        
        await logger.log("OpusDecoder initialized: \(configuration)")
    }
    
    deinit {
        if let decoder = decoder {
            opus_decoder_destroy(decoder)
        }
        // Note: Cannot use async logger in deinit as it creates a retain cycle
        // The decoder cleanup is the critical part
    }
    
    // MARK: - Setup
    
    private func setupDecoder() async throws {
        var error: Int32 = 0
        
        // Create Opus decoder
        decoder = opus_decoder_create(
            Int32(configuration.sampleRate),
            Int32(configuration.channels),
            &error
        )
        
        guard error == OPUS_OK, decoder != nil else {
            throw OpusError.decodingFailed(reason: "Failed to create decoder: \(getErrorString(error))")
        }
        
        await logger.log("OpusDecoder created successfully")
    }
    
    // MARK: - AudioDecoderProtocol
    
    public func decode(_ opusData: Data) async throws -> Data {
        guard let decoder = decoder else {
            throw OpusError.decoderNotInitialized
        }
        
        guard !opusData.isEmpty else {
            throw OpusError.decodingFailed(reason: "Empty Opus data")
        }
        
        // Decode the Opus packet
        let maxFrameSize = OpusConstants.maxFrameSize
        let pcmSize = maxFrameSize * configuration.channels * MemoryLayout<Int16>.size
        var pcmData = Data(count: pcmSize)
        
        let decodedSamples = try opusData.withUnsafeBytes { (opusBytes: UnsafeRawBufferPointer) -> Int32 in
            try pcmData.withUnsafeMutableBytes { (pcmBytes: UnsafeMutableRawBufferPointer) -> Int32 in
                let opusPointer = opusBytes.bindMemory(to: UInt8.self)
                let pcmPointer = pcmBytes.bindMemory(to: Int16.self)
                
                // Guard base addresses for safety
                guard let opusBase = opusPointer.baseAddress else {
                    throw OpusError.decodingFailed(reason: "Opus data pointer was nil")
                }
                guard let pcmBase = pcmPointer.baseAddress else {
                    throw OpusError.decodingFailed(reason: "PCM buffer pointer was nil")
                }
                
                let samples = opus_decode(
                    decoder,
                    opusBase,
                    Int32(opusData.count),
                    pcmBase,
                    Int32(maxFrameSize),
                    0 // decode_fec (forward error correction)
                )
                
                guard samples > 0 else {
                    throw OpusError.decodingFailed(reason: "Decoding failed: \(getErrorString(samples))")
                }
                
                return samples
            }
        }
        
        // Return only the decoded bytes
        let actualSize = Int(decodedSamples) * configuration.channels * MemoryLayout<Int16>.size
        let result = pcmData.prefix(actualSize)
        
        await logger.log("Decoded \(opusData.count) bytes to \(result.count) bytes", level: .debug)
        return result
    }
    
    public func decodeFile(at url: URL) async throws -> URL {
        await logger.log("Decoding file: \(url.lastPathComponent)", level: .info)
        
        // Load Opus data
        guard let opusData = try? Data(contentsOf: url) else {
            throw OpusError.fileNotFound(path: url.path)
        }
        
        // Decode
        let pcmData = try await decode(opusData)
        
        // Create output URL
        let outputURL = url.deletingPathExtension().appendingPathExtension("pcm")
        
        // Write decoded data
        try pcmData.write(to: outputURL, options: .atomic)
        
        await logger.log("Decoded file saved: \(outputURL.lastPathComponent)", level: .info)
        return outputURL
    }
    
    public func decodeStream(_ opusData: Data) async throws -> AVAudioPCMBuffer {
        guard let decoder = decoder else {
            throw OpusError.decoderNotInitialized
        }
        
        // Decode to PCM data
        let pcmData = try await decode(opusData)
        
        // Create audio format
        guard let format = AVAudioFormat.opusPCMFormat(
            sampleRate: Double(configuration.sampleRate),
            channels: AVAudioChannelCount(configuration.channels)
        ) else {
            throw OpusError.invalidAudioFormat(reason: "Failed to create audio format")
        }
        
        // Calculate frame count
        let bytesPerFrame = configuration.channels * MemoryLayout<Int16>.size
        let frameCount = pcmData.count / bytesPerFrame
        
        // Create buffer
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw OpusError.bufferAllocationFailed
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Copy PCM data to buffer
        guard let channelData = buffer.int16ChannelData else {
            throw OpusError.invalidAudioFormat(reason: "Buffer must be Int16 format")
        }
        
        pcmData.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            
            if configuration.channels == 1 {
                // Mono
                let channel0 = channelData[0]
                for i in 0..<frameCount {
                    channel0[i] = int16Ptr[i]
                }
            } else {
                // Stereo - deinterleave
                let channel0 = channelData[0]
                let channel1 = channelData[1]
                for i in 0..<frameCount {
                    channel0[i] = int16Ptr[i * 2]
                    channel1[i] = int16Ptr[i * 2 + 1]
                }
            }
        }
        
        return buffer
    }
    
    // MARK: - Private Helpers
    
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
