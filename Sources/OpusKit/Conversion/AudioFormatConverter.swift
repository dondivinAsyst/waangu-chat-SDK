import Foundation
import AVFoundation
import WaanguCoreKit

/// Converts audio between different formats
public actor AudioFormatConverter: AudioConverterProtocol {
    
    private let logger: AppLogger
    private let fileManager: AudioFileManager
    
    public init(
        fileManager: AudioFileManager,
        logger: AppLogger = .shared
    ) {
        self.fileManager = fileManager
        self.logger = logger
    }
    
    public func convert(from sourceURL: URL, to targetFormat: AudioFormat) async throws -> URL {
        await logger.log("Converting \(sourceURL.lastPathComponent) to \(targetFormat.rawValue)")
        
        guard await fileManager.fileExists(at: sourceURL) else {
            throw OpusError.fileNotFound(path: sourceURL.path)
        }
        
        // Create output URL
        let outputURL = sourceURL.deletingPathExtension().appendingPathExtension(targetFormat.fileExtension)
        
        // Load source file
        let audioFile = try AVAudioFile(forReading: sourceURL)
        let sourceFormat = audioFile.processingFormat
        
        // Create target format
        guard let targetAudioFormat = createAudioFormat(for: targetFormat, sampleRate: sourceFormat.sampleRate) else {
            throw OpusError.invalidAudioFormat(reason: "Failed to create target format")
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetAudioFormat) else {
            throw OpusError.conversionFailed(reason: "Failed to create audio converter")
        }
        
        // Create output file
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: targetAudioFormat.settings,
            commonFormat: targetAudioFormat.commonFormat,
            interleaved: targetAudioFormat.isInterleaved
        )
        
        // Convert in chunks
        let bufferSize: AVAudioFrameCount = 4096
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: bufferSize) else {
            throw OpusError.bufferAllocationFailed
        }
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetAudioFormat, frameCapacity: bufferSize) else {
            throw OpusError.bufferAllocationFailed
        }
        
        while audioFile.framePosition < audioFile.length {
            let framesToRead = min(bufferSize, AVAudioFrameCount(audioFile.length - audioFile.framePosition))
            try audioFile.read(into: inputBuffer, frameCount: framesToRead)
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }
            
            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                throw OpusError.conversionFailed(reason: error.localizedDescription)
            }
            
            try outputFile.write(from: outputBuffer)
        }
        
        await logger.log("Conversion complete: \(outputURL.lastPathComponent)")
        return outputURL
    }
    
    nonisolated public func supportsConversion(from sourceFormat: AudioFormat, to targetFormat: AudioFormat) -> Bool {
        // Opus requires special handling via OpusEncoder/Decoder
        if sourceFormat == .opus || targetFormat == .opus {
            return false // Use OpusEncoder/Decoder directly
        }
        
        // Standard formats supported by AVFoundation
        let supportedFormats: Set<AudioFormat> = [.wav, .m4a, .mp3, .aac, .pcm]
        return supportedFormats.contains(sourceFormat) && supportedFormats.contains(targetFormat)
    }
    
    private func createAudioFormat(for format: AudioFormat, sampleRate: Double) -> AVAudioFormat? {
        switch format {
        case .pcm, .wav:
            return AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: true
            )
        case .m4a, .aac:
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        case .opus:
            return AVAudioFormat.opusPCMFormat(sampleRate: sampleRate, channels: 1)
        default:
            return nil
        }
    }
}
