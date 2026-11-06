import Foundation
import WaanguCoreKit

/// Specialized converter for PCM to Opus
public actor PCMToOpusConverter {
    
    private let encoder: OpusEncoder
    private let fileManager: AudioFileManager
    private let logger: AppLogger
    
    public init(
        configuration: OpusConfiguration = .voiceMessage,
        fileManager: AudioFileManager,
        logger: AppLogger = .shared
    ) async throws {
        self.encoder = try await OpusEncoder(configuration: configuration, logger: logger)
        self.fileManager = fileManager
        self.logger = logger
    }
    
    /// Convert PCM file to Opus
    public func convert(pcmURL: URL, configuration: OpusConfiguration = .voiceMessage) async throws -> URL {
        await logger.log("Converting PCM to Opus: \(pcmURL.lastPathComponent)", level: .info)
        
        // Load PCM data
        let pcmData = try await fileManager.load(from: pcmURL)
        
        // Encode to Opus
        let opusData = try await encoder.encode(pcmData, configuration: configuration)
        
        // Create output URL
        let outputURL = pcmURL.deletingPathExtension().appendingPathExtension("opus")
        
        // Save Opus data
        try await fileManager.save(opusData, to: outputURL)
        
        await logger.log("PCM to Opus conversion complete: \(outputURL.lastPathComponent)", level: .info)
        return outputURL
    }
}
