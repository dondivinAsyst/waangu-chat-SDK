import Foundation

/// Audio quality presets
public enum AudioQuality: Sendable {
    case low
    case medium
    case high
    case veryHigh
    
    /// Recommended bitrate for the quality level
    public var bitrate: Int {
        switch self {
        case .low: return 16_000      // 16 kbps
        case .medium: return 32_000   // 32 kbps
        case .high: return 64_000     // 64 kbps
        case .veryHigh: return 128_000 // 128 kbps
        }
    }
    
    /// Recommended sample rate for the quality level
    public var sampleRate: Int {
        switch self {
        case .low: return 16_000      // 16 kHz
        case .medium: return 24_000   // 24 kHz
        case .high: return 48_000     // 48 kHz
        case .veryHigh: return 48_000 // 48 kHz
        }
    }
}
