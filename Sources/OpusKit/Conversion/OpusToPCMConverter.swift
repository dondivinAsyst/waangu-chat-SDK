import Foundation
import WaanguCoreKit

/// Specialized converter for Opus to PCM
public actor OpusToPCMConverter {
    
    private let decoder: OpusDecoder
    private let fileManager: AudioFileManager
    private let logger: AppLogger
    
    public init(
        configuration: OpusConfiguration = .voiceMessage,
        fileManager: AudioFileManager,
        logger: AppLogger = .shared
    ) async throws {
        self.decoder = try await OpusDecoder(configuration: configuration, logger: logger)
        self.fileManager = fileManager
        self.logger = logger
    }
    
    /// Convert Opus file to PCM
    public func convert(opusURL: URL) async throws -> URL {
        await logger.log("Converting Opus to PCM: \(opusURL.lastPathComponent)", level: .info)
        
        // Load Opus data
        let opusData = try await fileManager.load(from: opusURL)
        
        // Decode to PCM
        let pcmData = try await decoder.decode(opusData)
        
        // Create output URL
        let outputURL = opusURL.deletingPathExtension().appendingPathExtension("pcm")
        
        // Save PCM data
        try await fileManager.save(pcmData, to: outputURL)
        
        await logger.log("Opus to PCM conversion complete: \(outputURL.lastPathComponent)", level: .info)
        return outputURL
    }
}
