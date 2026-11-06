import Foundation

/// Audio file metadata
public struct AudioMetadata: Sendable {
    public let duration: TimeInterval
    public let sampleRate: Int
    public let channels: Int
    public let bitrate: Int?
    public let format: AudioFormat
    public let fileSize: Int64
    
    public init(
        duration: TimeInterval,
        sampleRate: Int,
        channels: Int,
        bitrate: Int? = nil,
        format: AudioFormat,
        fileSize: Int64
    ) {
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitrate = bitrate
        self.format = format
        self.fileSize = fileSize
    }
}
