import Foundation

/// Protocol defining audio format conversion capabilities
public protocol AudioConverterProtocol: Sendable {
    /// Convert audio from one format to another
    /// - Parameters:
    ///   - sourceURL: URL of the source audio file
    ///   - targetFormat: Target audio format
    /// - Returns: URL of the converted audio file
    func convert(from sourceURL: URL, to targetFormat: AudioFormat) async throws -> URL
    
    /// Check if conversion is supported
    /// - Parameters:
    ///   - sourceFormat: Source audio format
    ///   - targetFormat: Target audio format
    /// - Returns: True if conversion is supported
    func supportsConversion(from sourceFormat: AudioFormat, to targetFormat: AudioFormat) -> Bool
}
