import Foundation

/// Supported audio formats
public enum AudioFormat: String, Sendable {
    case opus = "opus"
    case pcm = "pcm"
    case wav = "wav"
    case m4a = "m4a"
    case mp3 = "mp3"
    case aac = "aac"
    
    /// File extension for the format
    public var fileExtension: String {
        switch self {
        case .opus: return "opus"
        case .pcm: return "pcm"
        case .wav: return "wav"
        case .m4a: return "m4a"
        case .mp3: return "mp3"
        case .aac: return "aac"
        }
    }
    
    /// MIME type for the format
    public var mimeType: String {
        switch self {
        case .opus: return "audio/opus"
        case .pcm: return "audio/pcm"
        case .wav: return "audio/wav"
        case .m4a: return "audio/mp4"
        case .mp3: return "audio/mpeg"
        case .aac: return "audio/aac"
        }
    }
}
