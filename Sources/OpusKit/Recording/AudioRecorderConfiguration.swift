import Foundation

/// Configuration for audio recording
public struct AudioRecorderConfiguration: Sendable {
    
    // MARK: - Properties
    
    /// Opus encoding configuration
    public let opusConfiguration: OpusConfiguration
    
    /// Maximum recording duration in seconds (nil for unlimited)
    public let maxDuration: TimeInterval?
    
    /// Output file URL (nil for auto-generated)
    public let outputURL: URL?
    
    /// Enable audio level monitoring
    public let enableLevelMonitoring: Bool
    
    /// Audio session category
    public let audioSessionCategory: AudioSessionCategory
    
    // MARK: - Audio Session Category
    
    public enum AudioSessionCategory: Sendable {
        case playAndRecord
        case record
        case playback
        
        public var systemCategory: String {
            switch self {
            case .playAndRecord: return "AVAudioSessionCategoryPlayAndRecord"
            case .record: return "AVAudioSessionCategoryRecord"
            case .playback: return "AVAudioSessionCategoryPlayback"
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(
        opusConfiguration: OpusConfiguration = .voiceMessage,
        maxDuration: TimeInterval? = nil,
        outputURL: URL? = nil,
        enableLevelMonitoring: Bool = false,
        audioSessionCategory: AudioSessionCategory = .record
    ) {
        self.opusConfiguration = opusConfiguration
        self.maxDuration = maxDuration
        self.outputURL = outputURL
        self.enableLevelMonitoring = enableLevelMonitoring
        self.audioSessionCategory = audioSessionCategory
    }
    
    // MARK: - Presets
    
    /// Default configuration for voice messages
    public static let voiceMessage = AudioRecorderConfiguration(
        opusConfiguration: .voiceMessage,
        maxDuration: 300, // 5 minutes
        enableLevelMonitoring: true,
        audioSessionCategory: .record
    )
    
    /// Configuration for voice calls
    public static let voiceCall = AudioRecorderConfiguration(
        opusConfiguration: .voiceChat,
        maxDuration: nil, // Unlimited
        enableLevelMonitoring: true,
        audioSessionCategory: .playAndRecord
    )
    
    /// Configuration for high quality recording
    public static let highQuality = AudioRecorderConfiguration(
        opusConfiguration: .highQualityAudio,
        maxDuration: nil,
        enableLevelMonitoring: false,
        audioSessionCategory: .record
    )
}
