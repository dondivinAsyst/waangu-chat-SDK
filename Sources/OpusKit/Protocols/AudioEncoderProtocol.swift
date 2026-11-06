import Foundation
import AVFoundation

/// Protocol defining audio encoding capabilities
public protocol AudioEncoderProtocol: Sendable {
    /// Encode PCM audio data to Opus format
    /// - Parameters:
    ///   - pcmData: Raw PCM audio data
    ///   - configuration: Opus encoding configuration
    /// - Returns: Encoded Opus data
    func encode(_ pcmData: Data, configuration: OpusConfiguration) async throws -> Data
    
    /// Encode audio file to Opus format
    /// - Parameters:
    ///   - url: URL of the source audio file
    ///   - configuration: Opus encoding configuration
    /// - Returns: URL of the encoded Opus file
    func encodeFile(at url: URL, configuration: OpusConfiguration) async throws -> URL
    
    /// Encode audio buffer for real-time streaming
    /// - Parameter pcmBuffer: PCM audio buffer
    /// - Returns: Encoded Opus data
    func encodeStream(_ pcmBuffer: AVAudioPCMBuffer) async throws -> Data
}
