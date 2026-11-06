import AVFoundation

extension AVAudioFormat {
    /// Create a standard PCM format for Opus encoding
    static func opusPCMFormat(
        sampleRate: Double,
        channels: AVAudioChannelCount
    ) -> AVAudioFormat? {
        return AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )
    }
    
    /// Check if format is compatible with Opus
    var isOpusCompatible: Bool {
        guard commonFormat == .pcmFormatInt16 || commonFormat == .pcmFormatFloat32 else {
            return false
        }
        
        let validSampleRates: [Double] = [8000, 12000, 16000, 24000, 48000]
        guard validSampleRates.contains(sampleRate) else {
            return false
        }
        
        guard channelCount >= 1 && channelCount <= 2 else {
            return false
        }
        
        return true
    }
}
