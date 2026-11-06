import Foundation

/// Constants used throughout OpusKit
public enum OpusConstants {
    
    // MARK: - Opus Library Constants
    
    /// Maximum packet size for Opus (4000 bytes)
    public static let maxPacketSize: Int = 4000
    
    /// Maximum frame size for 48kHz (120ms)
    public static let maxFrameSize: Int = 5760
    
    /// Minimum frame size (2.5ms at 48kHz)
    public static let minFrameSize: Int = 120
    
    // MARK: - Sample Rates
    
    public enum SampleRate {
        public static let narrowband = 8_000
        public static let mediumband = 12_000
        public static let wideband = 16_000
        public static let superWideband = 24_000
        public static let fullband = 48_000
        
        public static let all = [
            narrowband,
            mediumband,
            wideband,
            superWideband,
            fullband
        ]
    }
    
    // MARK: - Bitrates
    
    public enum Bitrate {
        public static let minimum = 6_000
        public static let maximum = 510_000
        public static let voipRecommended = 12_000
        public static let audioRecommended = 64_000
    }
    
    // MARK: - Frame Sizes (in milliseconds)
    
    public enum FrameSize {
        public static let veryShort = 5
        public static let short = 10
        public static let standard = 20
        public static let long = 40
        public static let veryLong = 60
        
        public static let all = [veryShort, short, standard, long, veryLong]
    }
    
    // MARK: - File Extensions
    
    public static let opusFileExtension = "opus"
    public static let oggFileExtension = "ogg"
    public static let wavFileExtension = "wav"
    
    // MARK: - MIME Types
    
    public static let opusMimeType = "audio/opus"
    public static let oggMimeType = "audio/ogg"
    public static let wavMimeType = "audio/wav"
    
    // MARK: - Buffer Sizes
    
    /// Default buffer size for audio processing
    public static let defaultBufferSize = 4096
    
    /// Maximum buffer pool size
    public static let maxBufferPoolSize = 10
    
    // MARK: - Opus Error Codes
    
    public enum OpusErrorCode: Int32 {
        case ok = 0
        case badArg = -1
        case bufferTooSmall = -2
        case internalError = -3
        case invalidPacket = -4
        case unimplemented = -5
        case invalidState = -6
        case allocFail = -7
        
        public var description: String {
            switch self {
            case .ok: return "OK"
            case .badArg: return "Bad argument"
            case .bufferTooSmall: return "Buffer too small"
            case .internalError: return "Internal error"
            case .invalidPacket: return "Invalid packet"
            case .unimplemented: return "Unimplemented"
            case .invalidState: return "Invalid state"
            case .allocFail: return "Allocation failed"
            }
        }
    }
}
