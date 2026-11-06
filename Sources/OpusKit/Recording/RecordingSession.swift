import Foundation

/// Represents an active recording session
public struct RecordingSession: Sendable {
    public let id: UUID
    public let startTime: Date
    public let configuration: AudioRecorderConfiguration
    public let outputURL: URL
    
    public init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        configuration: AudioRecorderConfiguration,
        outputURL: URL
    ) {
        self.id = id
        self.startTime = startTime
        self.configuration = configuration
        self.outputURL = outputURL
    }
    
    /// Calculate elapsed time
    public func elapsedTime(pausedDuration: TimeInterval = 0) -> TimeInterval {
        return Date().timeIntervalSince(startTime) - pausedDuration
    }
}
