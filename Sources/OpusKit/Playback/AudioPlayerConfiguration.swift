import Foundation

/// Configuration for audio playback
public struct AudioPlayerConfiguration: Sendable {
    
    /// Playback rate (0.5 = half speed, 1.0 = normal, 2.0 = double speed)
    public let playbackRate: Float
    
    /// Volume (0.0 = silent, 1.0 = full volume)
    public let volume: Float
    
    /// Enable audio level monitoring during playback
    public let enableLevelMonitoring: Bool
    
    public init(
        playbackRate: Float = 1.0,
        volume: Float = 1.0,
        enableLevelMonitoring: Bool = false
    ) {
        self.playbackRate = max(0.5, min(2.0, playbackRate))
        self.volume = max(0.0, min(1.0, volume))
        self.enableLevelMonitoring = enableLevelMonitoring
    }
    
    /// Default configuration
    public static let `default` = AudioPlayerConfiguration()
    
    /// Configuration for voice messages
    public static let voiceMessage = AudioPlayerConfiguration(
        playbackRate: 1.0,
        volume: 1.0,
        enableLevelMonitoring: false
    )
}
