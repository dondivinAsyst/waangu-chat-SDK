import Foundation
import AVFoundation

/// Protocol defining audio decoding capabilities
public protocol AudioDecoderProtocol: Sendable {
    /// Decode Opus data to PCM format
    /// - Parameter opusData: Encoded Opus data
    /// - Returns: Decoded PCM audio data
    func decode(_ opusData: Data) async throws -> Data
    
    /// Decode Opus file to PCM format
    /// - Parameter url: URL of the Opus file
    /// - Returns: URL of the decoded PCM file
    func decodeFile(at url: URL) async throws -> URL
    
    /// Decode Opus data to audio buffer for real-time playback
    /// - Parameter opusData: Encoded Opus data
    /// - Returns: PCM audio buffer ready for playback
    func decodeStream(_ opusData: Data) async throws -> AVAudioPCMBuffer
}
