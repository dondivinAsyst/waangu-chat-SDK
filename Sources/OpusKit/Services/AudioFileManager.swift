import Foundation
import WaanguCoreKit

/// Manages audio file operations
public actor AudioFileManager {
    private let logger: AppLogger
    private let fileManager: FileManager
    
    public init(logger: AppLogger = .shared, fileManager: FileManager = .default) {
        self.logger = logger
        self.fileManager = fileManager
    }
    
    // MARK: - File Operations
    
    /// Save audio data to file
    /// - Parameters:
    ///   - data: Audio data to save
    ///   - url: Destination URL
    public func save(_ data: Data, to url: URL) throws {
        do {
            // Create directory if needed
            let directory = url.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            // Write data
            try data.write(to: url, options: .atomic)
            Task {
                await logger.log("Saved audio file: \(url.lastPathComponent) (\(data.count) bytes)", level: .info)
            }
        } catch {
            Task {
                await logger.log("Failed to save audio file: \(error.localizedDescription)", level: .error)
            }
            throw OpusError.fileOperationFailed(reason: error.localizedDescription)
        }
    }
    
    /// Load audio data from file
    /// - Parameter url: Source URL
    /// - Returns: Audio data
    public func load(from url: URL) throws -> Data {
        do {
            guard fileManager.fileExists(atPath: url.path) else {
                throw OpusError.fileNotFound(path: url.path)
            }
            
            let data = try Data(contentsOf: url)
            Task {
                await logger.log("Loaded audio file: \(url.lastPathComponent) (\(data.count) bytes)", level: .info)
            }
            return data
        } catch let error as OpusError {
            throw error
        } catch {
            Task {
                await logger.log("Failed to load audio file: \(error.localizedDescription)", level: .error)
            }
            throw OpusError.fileOperationFailed(reason: error.localizedDescription)
        }
    }
    
    /// Delete audio file
    /// - Parameter url: File URL to delete
    public func delete(at url: URL) throws {
        do {
            guard fileManager.fileExists(atPath: url.path) else {
                Task {
                    await logger.log("File not found for deletion: \(url.lastPathComponent)", level: .warning)
                }
                return
            }
            
            try fileManager.removeItem(at: url)
            Task {
                await logger.log("Deleted audio file: \(url.lastPathComponent)", level: .info)
            }
        } catch {
            Task {
                await logger.log("Failed to delete audio file: \(error.localizedDescription)", level: .error)
            }
            throw OpusError.fileOperationFailed(reason: error.localizedDescription)
        }
    }
    
    /// Move audio file
    /// - Parameters:
    ///   - source: Source URL
    ///   - destination: Destination URL
    public func move(from source: URL, to destination: URL) throws {
        do {
            guard fileManager.fileExists(atPath: source.path) else {
                throw OpusError.fileNotFound(path: source.path)
            }
            
            // Create destination directory if needed
            let directory = destination.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            // Remove destination if exists
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            
            try fileManager.moveItem(at: source, to: destination)
            Task {
                await logger.log("Moved audio file: \(source.lastPathComponent) -> \(destination.lastPathComponent)", level: .info)
            }
        } catch let error as OpusError {
            throw error
        } catch {
            Task {
                await logger.log("Failed to move audio file: \(error.localizedDescription)", level: .error)
            }
            throw OpusError.fileOperationFailed(reason: error.localizedDescription)
        }
    }
    
    /// Copy audio file
    /// - Parameters:
    ///   - source: Source URL
    ///   - destination: Destination URL
    public func copy(from source: URL, to destination: URL) throws {
        do {
            guard fileManager.fileExists(atPath: source.path) else {
                throw OpusError.fileNotFound(path: source.path)
            }
            
            // Create destination directory if needed
            let directory = destination.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            // Remove destination if exists
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            
            try fileManager.copyItem(at: source, to: destination)
            Task {
                await logger.log("Copied audio file: \(source.lastPathComponent) -> \(destination.lastPathComponent)", level: .info)
            }
        } catch let error as OpusError {
            throw error
        } catch {
            Task {
                await logger.log("Failed to copy audio file: \(error.localizedDescription)", level: .error)
            }
            throw OpusError.fileOperationFailed(reason: error.localizedDescription)
        }
    }
    
    /// Check if file exists
    /// - Parameter url: File URL
    /// - Returns: True if file exists
    public func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }
    
    /// Get file metadata
    /// - Parameter url: File URL
    /// - Returns: Audio metadata
    public func getMetadata(for url: URL) throws -> AudioMetadata {
        guard fileManager.fileExists(atPath: url.path) else {
            throw OpusError.fileNotFound(path: url.path)
        }
        
        guard let format = url.audioFormat else {
            throw OpusError.invalidAudioFormat(reason: "Unknown format for file: \(url.lastPathComponent)")
        }
        
        guard let fileSize = url.fileSize else {
            throw OpusError.fileOperationFailed(reason: "Could not get file size")
        }
        
        // For now, return basic metadata
        // TODO: Parse actual audio file headers for accurate metadata
        return AudioMetadata(
            duration: 0,
            sampleRate: 48000,
            channels: 1,
            bitrate: nil,
            format: format,
            fileSize: fileSize
        )
    }
    
    // MARK: - Temporary Files
    
    /// Create a temporary file URL
    /// - Parameter format: Audio format
    /// - Returns: Temporary file URL
    public func createTemporaryURL(format: AudioFormat) -> URL {
        return URL.temporaryAudioFile(format: format)
    }
    
    /// Clean up temporary files
    public func cleanupTemporaryFiles() {
        let tempDir = fileManager.temporaryDirectory
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: nil
            )
            
            let audioFiles = contents.filter { $0.isAudioFile }
            
            for file in audioFiles {
                try? fileManager.removeItem(at: file)
            }
            
            Task {
                await logger.log("Cleaned up \(audioFiles.count) temporary audio files", level: .info)
            }
        } catch {
            Task {
                await logger.log("Failed to cleanup temporary files: \(error.localizedDescription)", level: .error)
            }
        }
    }
}
