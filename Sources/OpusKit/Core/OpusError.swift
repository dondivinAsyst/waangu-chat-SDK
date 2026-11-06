import Foundation

/// Errors that can occur during Opus operations
public enum OpusError: Error, LocalizedError, Sendable {
    case encodingFailed(reason: String)
    case decodingFailed(reason: String)
    case invalidConfiguration(reason: String)
    case invalidAudioFormat(reason: String)
    case fileNotFound(path: String)
    case permissionDenied(permission: String)
    case bufferAllocationFailed
    case unsupportedSampleRate(Int)
    case unsupportedChannelCount(Int)
    case recordingFailed(reason: String)
    case playbackFailed(reason: String)
    case conversionFailed(reason: String)
    case invalidFrameSize(Int)
    case encoderNotInitialized
    case decoderNotInitialized
    case audioSessionError(reason: String)
    case fileOperationFailed(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let reason):
            return "Opus encoding failed: \(reason)"
        case .decodingFailed(let reason):
            return "Opus decoding failed: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .invalidAudioFormat(let reason):
            return "Invalid audio format: \(reason)"
        case .fileNotFound(let path):
            return "Audio file not found at: \(path)"
        case .permissionDenied(let permission):
            return "Permission denied: \(permission)"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .unsupportedSampleRate(let rate):
            return "Unsupported sample rate: \(rate) Hz. Supported rates: 8000, 12000, 16000, 24000, 48000"
        case .unsupportedChannelCount(let count):
            return "Unsupported channel count: \(count). Supported: 1 (mono) or 2 (stereo)"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .playbackFailed(let reason):
            return "Playback failed: \(reason)"
        case .conversionFailed(let reason):
            return "Audio conversion failed: \(reason)"
        case .invalidFrameSize(let size):
            return "Invalid frame size: \(size) ms. Valid values: 5, 10, 20, 40, 60"
        case .encoderNotInitialized:
            return "Opus encoder not initialized"
        case .decoderNotInitialized:
            return "Opus decoder not initialized"
        case .audioSessionError(let reason):
            return "Audio session error: \(reason)"
        case .fileOperationFailed(let reason):
            return "File operation failed: \(reason)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .unsupportedSampleRate:
            return "Use one of the supported sample rates: 8000, 12000, 16000, 24000, or 48000 Hz"
        case .unsupportedChannelCount:
            return "Use mono (1 channel) or stereo (2 channels)"
        case .permissionDenied:
            return "Grant the required permission in Settings"
        case .invalidFrameSize:
            return "Use one of the valid frame sizes: 5, 10, 20, 40, or 60 ms"
        case .bufferAllocationFailed:
            return "Free up memory and try again"
        default:
            return nil
        }
    }
}
