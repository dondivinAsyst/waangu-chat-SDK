import Foundation

/// Configuration for Opus encoding/decoding
public struct OpusConfiguration: Sendable {
    
    // MARK: - Bitrate
    
    public enum Bitrate: Sendable {
        case voip          // 8-12 kbps - optimized for voice
        case narrowband    // 16 kbps
        case mediumband    // 24 kbps
        case wideband      // 32 kbps
        case superWideband // 48 kbps
        case fullband      // 64-128 kbps - high quality audio
        case custom(Int)
        
        public var value: Int {
            switch self {
            case .voip: return 12_000
            case .narrowband: return 16_000
            case .mediumband: return 24_000
            case .wideband: return 32_000
            case .superWideband: return 48_000
            case .fullband: return 96_000
            case .custom(let value): return value
            }
        }
    }
    
    // MARK: - Application Type
    
    public enum Application: Int32, Sendable {
        case voip = 2048          // OPUS_APPLICATION_VOIP
        case audio = 2049         // OPUS_APPLICATION_AUDIO
        case restrictedLowDelay = 2051 // OPUS_APPLICATION_RESTRICTED_LOWDELAY
        
        public var description: String {
            switch self {
            case .voip: return "VOIP (optimized for voice)"
            case .audio: return "Audio (optimized for music)"
            case .restrictedLowDelay: return "Restricted Low Delay"
            }
        }
    }
    
    // MARK: - Complexity
    
    public enum Complexity: Int32, Sendable {
        case low = 3       // 0-3
        case medium = 6    // 4-7
        case high = 9      // 8-10
        
        public var value: Int32 {
            return self.rawValue
        }
    }
    
    // MARK: - Properties
    
    public let sampleRate: Int
    public let channels: Int
    public let bitrate: Bitrate
    public let application: Application
    public let complexity: Complexity
    public let useVBR: Bool           // Variable Bitrate
    public let useDTX: Bool           // Discontinuous Transmission
    public let frameSize: Int         // Frame size in milliseconds
    
    // MARK: - Initialization
    
    public init(
        sampleRate: Int,
        channels: Int,
        bitrate: Bitrate,
        application: Application,
        complexity: Complexity,
        useVBR: Bool,
        useDTX: Bool,
        frameSize: Int
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitrate = bitrate
        self.application = application
        self.complexity = complexity
        self.useVBR = useVBR
        self.useDTX = useDTX
        self.frameSize = frameSize
    }
    
    // MARK: - Presets
    
    /// Optimized for voice chat (low bandwidth, good quality)
    public static let voiceChat = OpusConfiguration(
        sampleRate: 16_000,
        channels: 1,
        bitrate: .voip,
        application: .voip,
        complexity: .medium,
        useVBR: true,
        useDTX: true,
        frameSize: 20
    )
    
    /// Optimized for high quality audio (music, podcasts)
    public static let highQualityAudio = OpusConfiguration(
        sampleRate: 48_000,
        channels: 2,
        bitrate: .fullband,
        application: .audio,
        complexity: .high,
        useVBR: true,
        useDTX: false,
        frameSize: 20
    )
    
    /// Optimized for low latency applications
    public static let lowLatency = OpusConfiguration(
        sampleRate: 48_000,
        channels: 1,
        bitrate: .wideband,
        application: .restrictedLowDelay,
        complexity: .low,
        useVBR: false,
        useDTX: false,
        frameSize: 10
    )
    
    /// Optimized for voice messages (balance of quality and size)
    public static let voiceMessage = OpusConfiguration(
        sampleRate: 24_000,
        channels: 1,
        bitrate: .mediumband,
        application: .voip,
        complexity: .medium,
        useVBR: true,
        useDTX: true,
        frameSize: 20
    )
    
    // MARK: - Validation
    
    /// Validate configuration parameters
    public func validate() throws {
        // Validate sample rate
        let validSampleRates = [8_000, 12_000, 16_000, 24_000, 48_000]
        guard validSampleRates.contains(sampleRate) else {
            throw OpusError.unsupportedSampleRate(sampleRate)
        }
        
        // Validate channels
        guard channels >= 1 && channels <= 2 else {
            throw OpusError.unsupportedChannelCount(channels)
        }
        
        // Validate frame size
        let validFrameSizes = [5, 10, 20, 40, 60]
        guard validFrameSizes.contains(frameSize) else {
            throw OpusError.invalidConfiguration(reason: "Invalid frame size: \(frameSize)ms. Valid values: 5, 10, 20, 40, 60")
        }
        
        // Validate bitrate
        let bitrateValue = bitrate.value
        guard bitrateValue >= 6_000 && bitrateValue <= 510_000 else {
            throw OpusError.invalidConfiguration(reason: "Bitrate must be between 6000 and 510000 bps")
        }
    }
    
    /// Calculate frame size in samples
    public var frameSizeInSamples: Int {
        return (sampleRate * frameSize) / 1000
    }
}

// MARK: - CustomStringConvertible

extension OpusConfiguration: CustomStringConvertible {
    public var description: String {
        """
        OpusConfiguration(
            sampleRate: \(sampleRate) Hz,
            channels: \(channels),
            bitrate: \(bitrate.value) bps,
            application: \(application.description),
            complexity: \(complexity.rawValue),
            VBR: \(useVBR),
            DTX: \(useDTX),
            frameSize: \(frameSize) ms
        )
        """
    }
}
