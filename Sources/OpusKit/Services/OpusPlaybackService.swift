import Foundation
import AVFoundation
import WaanguCoreKit

/// Service for decoding and playing Opus audio files
public actor OpusPlaybackService: OpusPlaybackServiceProtocol {
    
    private let decoder: OpusDecoder
    private let logger: AppLogger
    private let fileManager: AudioFileManager
    
    // Cache for decoded files
    private static let decodedCache = NSCache<NSString, NSURL>()
    
    public init(
        logger: AppLogger = .shared,
        fileManager: AudioFileManager = AudioFileManager()
    ) async throws {
        self.logger = logger
        self.fileManager = fileManager
        
        // Initialize decoder with standard configuration for playback
        let config = OpusConfiguration(
            sampleRate: 48000,
            channels: 1,
            bitrate: .voip,
            application: .voip,
            complexity: .medium,
            useVBR: true,
            useDTX: false,
            frameSize: 20
        )
        self.decoder = try await OpusDecoder(
            configuration: config,
            logger: logger
        )
        
        await logger.log("OpusPlaybackService initialized", level: .info)
    }
    
    /// Decode Opus file to WAV for playback with AVAudioPlayer
    /// Returns URL of decoded WAV file (cached)
    public func decodeForPlayback(opusURL: URL) async throws -> URL {
        let cacheKey = opusURL.lastPathComponent as NSString
        
        // Check cache first
        if let cachedURL = Self.decodedCache.object(forKey: cacheKey) as URL? {
            if FileManager.default.fileExists(atPath: cachedURL.path) {
                await logger.log("Using cached decoded audio: \(cachedURL.lastPathComponent)", level: .debug)
                return cachedURL
            }
        }
        
        // Validate file exists and has content
        guard FileManager.default.fileExists(atPath: opusURL.path) else {
            throw OpusError.fileNotFound(path: opusURL.path)
        }
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: opusURL.path)[.size] as? Int64 ?? 0
        guard fileSize > 0 else {
            throw OpusError.decodingFailed(reason: "Opus file is empty (0 bytes)")
        }
        
        await logger.log("Decoding Opus file: \(opusURL.lastPathComponent) (size: \(fileSize) bytes)", level: .info)
        
        // Read Ogg Opus file and extract raw Opus packets
        let oggReader = OggOpusReader()
        
        await logger.log("Reading Ogg container...", level: .debug)
        
        let metadata: OggOpusMetadata
        do {
            metadata = try oggReader.readMetadata(from: opusURL)
            await logger.log("Metadata: sampleRate=\(metadata.sampleRate), channels=\(metadata.channels), preSkip=\(metadata.preSkip)", level: .debug)
        } catch {
            await logger.log("Failed to read metadata: \(error.localizedDescription)", level: .error)
            throw error
        }
        
        let opusPackets: [Data]
        do {
            opusPackets = try oggReader.readPackets(from: opusURL)
            await logger.log("Extracted \(opusPackets.count) Opus packets from Ogg container", level: .info)
        } catch {
            await logger.log("Failed to extract packets: \(error.localizedDescription)", level: .error)
            throw error
        }
        
        // Create decoder with matching sample rate if different from default
        let decoderToUse: OpusDecoder
        if metadata.sampleRate != 48000 {
            await logger.log("Creating decoder with sample rate: \(metadata.sampleRate) Hz", level: .debug)
            let config = OpusConfiguration(
                sampleRate: metadata.sampleRate,
                channels: metadata.channels,
                bitrate: .voip,
                application: .voip,
                complexity: .medium,
                useVBR: true,
                useDTX: false,
                frameSize: 20
            )
            decoderToUse = try await OpusDecoder(configuration: config, logger: logger)
        } else {
            decoderToUse = decoder
        }
        
        // Decode all Opus packets to PCM
        var allPCMData = Data()
        var successfulPackets = 0
        
        for (index, opusPacket) in opusPackets.enumerated() {
            do {
                let pcmData = try await decoderToUse.decode(opusPacket)
                allPCMData.append(pcmData)
                successfulPackets += 1
            } catch {
                await logger.log("Failed to decode packet \(index)/\(opusPackets.count): \(error.localizedDescription)", level: .warning)
                // Continue with other packets - some packets may fail but we can still play partial audio
            }
        }
        
        guard !allPCMData.isEmpty else {
            throw OpusError.decodingFailed(reason: "No PCM data decoded from \(opusPackets.count) Opus packets")
        }
        
        await logger.log("Successfully decoded \(successfulPackets)/\(opusPackets.count) packets → \(allPCMData.count) bytes of PCM data", level: .info)
        
        // Create WAV file from PCM
        let wavURL = try await createWAVFile(
            from: allPCMData, 
            sampleRate: metadata.sampleRate, 
            channels: metadata.channels
        )
        
        // Cache the decoded file
        Self.decodedCache.setObject(wavURL as NSURL, forKey: cacheKey)
        
        await logger.log("Decoded audio saved: \(wavURL.lastPathComponent) (duration: ~\(Double(allPCMData.count) / Double(metadata.sampleRate * metadata.channels * 2))s)", level: .info)
        
        return wavURL
    }
    
    /// Create WAV file from PCM data
    private func createWAVFile(from pcmData: Data, sampleRate: Int, channels: Int) async throws -> URL {
        // Create temporary WAV file
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent("\(UUID().uuidString).wav")
        
        // WAV header
        let dataSize = UInt32(pcmData.count)
        let fileSize = dataSize + 36
        
        var header = Data()
        
        // RIFF chunk
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // fmt chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // audio format (PCM)
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Data($0) }) // channels
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) }) // sample rate
        
        let byteRate = sampleRate * channels * 2 // 16-bit
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Data($0) }) // byte rate
        
        let blockAlign = channels * 2
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Data($0) }) // block align
        header.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // bits per sample
        
        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        
        // Write WAV file
        var wavData = header
        wavData.append(pcmData)
        try wavData.write(to: wavURL)
        
        return wavURL
    }
    
    /// Clear decoded audio cache
    public func clearCache() async {
        Self.decodedCache.removeAllObjects()
        await logger.log("Decoded audio cache cleared", level: .info)
    }
}
