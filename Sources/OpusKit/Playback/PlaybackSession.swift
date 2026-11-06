import Foundation

/// Represents an active playback session
public struct PlaybackSession: Sendable {
    public let id: UUID
    public let startTime: Date
    public let configuration: AudioPlayerConfiguration
    public let audioURL: URL
    public let duration: TimeInterval
    
    public init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        configuration: AudioPlayerConfiguration,
        audioURL: URL,
        duration: TimeInterval
    ) {
        self.id = id
        self.startTime = startTime
        self.configuration = configuration
        self.audioURL = audioURL
        self.duration = duration
    }
    
    /// Calculate elapsed time
    public func elapsedTime() -> TimeInterval {
        return Date().timeIntervalSince(startTime)
    }
    
    /// Calculate progress (0.0 - 1.0)
    public func progress() -> Double {
        guard duration > 0 else { return 0 }
        return min(1.0, elapsedTime() / duration)
    }
}
