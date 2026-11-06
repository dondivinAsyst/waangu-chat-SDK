import Foundation

/// Protocol defining audio playback capabilities
public protocol AudioPlayerProtocol: Sendable {
    /// Current playback state
    var isPlaying: Bool { get async }
    
    /// Current playback time in seconds
    var currentTime: TimeInterval { get async }
    
    /// Total duration of the audio in seconds
    var duration: TimeInterval { get async }
    
    /// Play audio from URL
    /// - Parameter url: URL of the audio file
    func play(url: URL) async throws
    
    /// Pause playback
    func pause() async throws
    
    /// Stop playback and reset position
    func stop() async throws
    
    /// Seek to specific time
    /// - Parameter time: Time in seconds
    func seek(to time: TimeInterval) async throws
}
