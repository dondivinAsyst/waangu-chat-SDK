import Foundation
import AVFoundation
import WaanguCoreKit
import opus

/// Synchronous Opus encoder for real-time audio recording
/// This encoder is NOT thread-safe and should only be used from a single serial queue
public final class OpusSyncEncoder {
    
    // MARK: - Properties
    
    private var encoder: OpaquePointer?
    private let configuration: OpusConfiguration
    
    // MARK: - Initialization
    
    public init(configuration: OpusConfiguration) throws {
        self.configuration = configuration
        
        // Validate configuration
        try configuration.validate()
        
        // Initialize encoder
        try setupEncoder()
    }
    
    deinit {
        if let encoder = encoder {
            opus_encoder_destroy(encoder)
        }
    }
    
    // MARK: - Setup
    
    private func setupEncoder() throws {
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
    }
    
    // MARK: - Synchronous Encoding
    
    /// Encode PCM buffer synchronously (real-time safe)
    public func encodeBuffer(_ buffer: AVAudioPCMBuffer) throws -> Data {
        guard let encoder = encoder else {
            throw OpusError.encoderNotInitialized
        }
        
        // Convert AVAudioPCMBuffer to Data
        guard let channelData = buffer.int16ChannelData else {
            throw OpusError.invalidAudioFormat(reason: "Buffer must be Int16 format")
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Encode directly
        return try encodeBufferDirect(
            channelData: channelData,
            frameLength: frameLength,
            channelCount: channelCount
        )
    }
    
    // MARK: - Private Helpers
    
    /// Encode buffer directly without data conversion (optimized for real-time)
    private func encodeBufferDirect(
        channelData: UnsafePointer<UnsafeMutablePointer<Int16>>,
        frameLength: Int,
        channelCount: Int
    ) throws -> Data {
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
