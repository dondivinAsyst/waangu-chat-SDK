import Foundation

/// Protocol defining audio recording capabilities
public protocol AudioRecorderProtocol: Sendable {
    /// Current recording state
    var isRecording: Bool { get async }
    
    /// Duration of current recording in seconds (wall-clock time)
    var recordingDuration: TimeInterval { get async }
    
    /// Actual audio duration based on encoded samples (not wall-clock time)
    var actualRecordingDuration: TimeInterval { get async }
    
    /// Start recording audio
    /// - Parameter configuration: Recording configuration
    func startRecording(configuration: AudioRecorderConfiguration) async throws
    
    /// Stop recording and return the file URL
    /// - Returns: URL of the recorded audio file
    func stopRecording() async throws -> URL
    
    /// Pause the current recording
    func pauseRecording() async throws
    
    /// Resume a paused recording
    func resumeRecording() async throws
    
    /// Cancel the current recording and discard the file
    func cancelRecording() async throws
}
