import Foundation
import AVFoundation

/// Wrapper for audio buffer data
public struct AudioBuffer: Sendable {
    public let data: Data
    public let format: AVAudioFormat
    public let frameCount: AVAudioFrameCount
    
    public init(data: Data, format: AVAudioFormat, frameCount: AVAudioFrameCount) {
        self.data = data
        self.format = format
        self.frameCount = frameCount
    }
    
    /// Create from AVAudioPCMBuffer
    public init?(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let dataSize = frameLength * channelCount * MemoryLayout<Float>.size
        
        var data = Data(count: dataSize)
        data.withUnsafeMutableBytes { ptr in
            let floatPtr = ptr.bindMemory(to: Float.self)
            for channel in 0..<channelCount {
                let channelPtr = channelData[channel]
                for frame in 0..<frameLength {
                    floatPtr[frame * channelCount + channel] = channelPtr[frame]
                }
            }
        }
        
        self.data = data
        self.format = buffer.format
        self.frameCount = buffer.frameLength
    }
}
