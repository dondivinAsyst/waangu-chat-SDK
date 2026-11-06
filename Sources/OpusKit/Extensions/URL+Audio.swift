import Foundation

extension URL {
    /// Check if URL points to an audio file
    var isAudioFile: Bool {
        let audioExtensions = ["opus", "ogg", "wav", "m4a", "mp3", "aac", "pcm"]
        return audioExtensions.contains(self.pathExtension.lowercased())
    }
    
    /// Get audio format from file extension
    var audioFormat: AudioFormat? {
        switch self.pathExtension.lowercased() {
        case "opus": return .opus
        case "pcm": return .pcm
        case "wav": return .wav
        case "m4a": return .m4a
        case "mp3": return .mp3
        case "aac": return .aac
        default: return nil
        }
    }
    
    /// Create a temporary audio file URL
    static func temporaryAudioFile(format: AudioFormat) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "audio_\(UUID().uuidString).\(format.fileExtension)"
        return tempDir.appendingPathComponent(filename)
    }
    
    /// Get file size in bytes
    var fileSize: Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: self.path) else {
            return nil
        }
        return attributes[.size] as? Int64
    }
}
