//
//  PathName.swift
//  AppModules
//
//  Created by Don divin on 5/5/26.
//


import SwiftUI
import Disk

public enum PathName:String {
    case STATUS = "status"
    case CHAT = "chat"
    
}

public class DiskMediaManager {
    
    public static let shared = DiskMediaManager()
    private init() {}
    
    /// Returns the file-system URL for a cached image, or nil if it doesn't exist.
    /// Checks JPEG first (new format), then PNG (legacy format).
    public func imageURL(for fileName: String, pathName: PathName) -> URL? {
        guard !fileName.isEmpty else { return nil }
        // Check JPEG first (new format — real compressed size)
        if let url = try? Disk.url(for: pathName.rawValue + "/\(fileName).jpg", in: .caches),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Fallback to PNG (legacy format)
        if let url = try? Disk.url(for: pathName.rawValue + "/\(fileName).png", in: .caches),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    public func hasDiskImage(for fileName: String, pathName: PathName) -> Bool {
        guard !fileName.isEmpty else { return false }
        // Check JPEG first (new format)
        if let url = try? Disk.url(for: pathName.rawValue + "/\(fileName).jpg", in: .caches),
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        // Fallback to PNG (legacy format)
        if let url = try? Disk.url(for: pathName.rawValue + "/\(fileName).png", in: .caches) {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return false
    }

    public func hasDiskVideo(for fileName: String, pathName: PathName) -> Bool {
        guard !fileName.isEmpty else { return false }
        // Use FileManager.fileExists instead of loading the full video URL
        guard let url = try? Disk.url(for: pathName.rawValue + "/\(fileName).mp4", in: .caches) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    public func loadImageFromDisk(fileName: String, pathName: PathName) -> UIImage? {
        // Try JPEG first (new format)
        if let url = try? Disk.url(for: pathName.rawValue + "/\(fileName).jpg", in: .caches),
           FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }
        // Fallback to PNG (legacy format)
        guard hasDiskImage(for: fileName, pathName: pathName) else { return nil }
        do {
            return try Disk.retrieve(pathName.rawValue + "/\(fileName).png", from: .caches, as: UIImage.self)
        } catch {
            #if DEBUG
            print("Error loading image: \(error)")
            #endif
            return nil
        }
    }
    
    public func getAllStoredCacheFiles(pathName: PathName) -> [URL] {
        do {
            let folderURL = try Disk.url(for: pathName.rawValue, in: .caches)
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return fileURLs
        } catch {
            #if DEBUG
            print("Error getting stored files: \(error)")
            #endif
            return []
        }
    }

    
//    func loadVideoFromDisk(fileName: String) -> URL? {
//        do {
//            return try Disk.retrieve("status/\(fileName).mp4", from: .caches, as: URL.self)
//        } catch {
//            print("Error loading video: \(error)")
//            return nil
//        }
//    }
//
    public func loadVideoFromDisk(fileName: String, pathName: PathName) -> URL? {
        do {
            let url = try Disk.url(for: pathName.rawValue + "/\(fileName).mp4", in: .caches)
            // Only return the URL if the file actually exists
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        } catch {
            #if DEBUG
            print("Error loading video path: \(error)")
            #endif
            return nil
        }
    }
    
    /// Save a UIImage to Disk
    public func saveImageToDisk(_ image: UIImage, fileName: String, pathName: PathName) {
        do {
            try Disk.save(image, to: .caches, as: pathName.rawValue + "/\(fileName).png")
          
        } catch {
            #if DEBUG
            print("Error saving image: \(error)")
            #endif
        }
    }
    
    /// Save raw image data (JPEG/PNG) directly to disk — preserves original file size and format
    public func saveImageDataToDisk(_ data: Data, fileName: String, pathName: PathName, asJPEG: Bool = true) {
        do {
            let ext = asJPEG ? "jpg" : "png"
            try Disk.save(data, to: .caches, as: pathName.rawValue + "/\(fileName).\(ext)")
        } catch {
            #if DEBUG
            print("Error saving image data: \(error)")
            #endif
        }
    }
    
    /// Returns the URL for a JPEG image (instead of PNG)
    public func imageJPEGURL(for fileName: String, pathName: PathName) -> URL? {
        guard !fileName.isEmpty else { return nil }
        guard let url = try? Disk.url(for: pathName.rawValue + "/\(fileName).jpg", in: .caches),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
    
    /// Save a video from URL (e.g., URL from camera or picker)
    ///
    /// - Returns: `false` when nothing was written. A silent failure here shows
    ///   up much later and far away as an upload failing with
    ///   "Local file not found", so callers should check it.
    @discardableResult
    public func saveVideoToDisk(from sourceURL: URL, fileName: String, pathName: PathName) -> Bool {
        do {
            let data = try Data(contentsOf: sourceURL)
            try Disk.save(data, to: .caches, as: pathName.rawValue + "/\(fileName).mp4")
            return true
        } catch {
            #if DEBUG
            print("Error saving video from \(sourceURL) (scheme: \(sourceURL.scheme ?? "none")): \(error)")
            #endif
            return false
        }
    }

    /// Copy a downloaded temp file into the status/chat video cache without loading it fully into memory.
    @discardableResult
    public func copyVideoToDisk(from sourceURL: URL, fileName: String, pathName: PathName) -> URL? {
        guard !fileName.isEmpty else { return nil }
        do {
            let relative = pathName.rawValue + "/\(fileName).mp4"
            let destination = try Disk.url(for: relative, in: .caches)
            let folder = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            #if DEBUG
            print("Error copying video to disk: \(error)")
            #endif
            return nil
        }
    }
    
    /// Save audio file to disk (for voice messages, audio files, etc.)
    @discardableResult
    public func saveAudioToDisk(from sourceURL: URL, fileName: String, pathName: PathName) -> URL? {
        do {
            let ext = sourceURL.pathExtension.lowercased()
            let data = try Data(contentsOf: sourceURL)
            return saveAudioDataToDisk(data: data, fileName: fileName, ext: ext, pathName: pathName)
        } catch {
            #if DEBUG
            print("❌ Error saving audio: \(error)")
            #endif
            return nil
        }
    }

    /// Save raw audio bytes with an explicit extension (URLSession temp files often have none).
    @discardableResult
    public func saveAudioDataToDisk(
        data: Data,
        fileName: String,
        ext: String,
        pathName: PathName
    ) -> URL? {
        do {
            let normalizedExt = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !fileName.isEmpty, !normalizedExt.isEmpty else { return nil }
            let path = pathName.rawValue + "/\(fileName).\(normalizedExt)"
            try Disk.save(data, to: .documents, as: path)
            let savedURL = try Disk.url(for: path, in: .documents)
            #if DEBUG
            print("✅ Audio saved to disk: \(fileName).\(normalizedExt)")
            #endif
            return savedURL
        } catch {
            #if DEBUG
            print("❌ Error saving audio data: \(error)")
            #endif
            return nil
        }
    }
    
    /// Load audio file from disk
    public func loadAudioFromDisk(fileName: String, ext: String, pathName: PathName) -> URL? {
        do {
            // Try documents first (new persistent location)
            let url = try Disk.url(for: pathName.rawValue + "/\(fileName).\(ext)", in: .documents)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            // Fallback to caches for legacy messages saved before this change
            let cacheUrl = try Disk.url(for: pathName.rawValue + "/\(fileName).\(ext)", in: .caches)
            guard FileManager.default.fileExists(atPath: cacheUrl.path) else { return nil }
            return cacheUrl
        } catch {
            #if DEBUG
            print("Error loading audio path: \(error)")
            #endif
            return nil
        }
    }
    
    /// Check if audio file exists on disk
    public func hasDiskAudio(for fileName: String, ext: String, pathName: PathName) -> Bool {
        guard !fileName.isEmpty else { return false }
        // Check documents first (new location)
        if let url = try? Disk.url(for: pathName.rawValue + "/\(fileName).\(ext)", in: .documents),
           FileManager.default.fileExists(atPath: url.path) { return true }
        // Fallback to caches for legacy
        guard let url = try? Disk.url(for: pathName.rawValue + "/\(fileName).\(ext)", in: .caches) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    // MARK: - Generic file persistence (documents, audio, etc.)

    @discardableResult
    public func saveFileToDisk(from sourceURL: URL, fileName: String, pathName: PathName) -> URL? {
        do {
            let ext = sourceURL.pathExtension.lowercased()
            let data = try Data(contentsOf: sourceURL)
            let path = pathName.rawValue + "/files/\(fileName).\(ext)"
            try Disk.save(data, to: .documents, as: path)
            return try Disk.url(for: path, in: .documents)
        } catch {
            #if DEBUG
            print("Error saving file: \(error)")
            #endif
            return nil
        }
    }

    @discardableResult
    public func saveFileDataToDisk(data: Data, fileName: String, ext: String, pathName: PathName) -> URL? {
        do {
            let normalizedExt = ext.lowercased()
            let path = pathName.rawValue + "/files/\(fileName).\(normalizedExt)"
            try Disk.save(data, to: .documents, as: path)
            return try Disk.url(for: path, in: .documents)
        } catch {
            #if DEBUG
            print("Error saving file data: \(error)")
            #endif
            return nil
        }
    }

    public func loadFileFromDisk(fileName: String, ext: String, pathName: PathName) -> URL? {
        do {
            let url = try Disk.url(for: pathName.rawValue + "/files/\(fileName).\(ext)", in: .documents)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        } catch {
            #if DEBUG
            print("Error loading file path: \(error)")
            #endif
            return nil
        }
    }

    func hasDiskFile(for fileName: String, ext: String, pathName: PathName) -> Bool {
        guard !fileName.isEmpty else { return false }
        guard let url = try? Disk.url(for: pathName.rawValue + "/files/\(fileName).\(ext)", in: .documents) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Tout ce que `path` garde sur l'appareil — fichiers sauvés et cache.
    func deleteEverything(in path: PathName) {
        for directory in [Disk.Directory.documents, .caches] {
            guard let url = try? Disk.url(for: path.rawValue, in: directory),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func deleteAllStoredCacheFilesFromPath(path: PathName) {
        do {
            let folderURL = try Disk.url(for: path.rawValue, in: .caches)
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in fileURLs {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            #if DEBUG
            print("Error deleting status files: \(error)")
            #endif
        }
    }

    func deleteStoredFiles(named targetNames: Set<String>, path: PathName) {
        do {
            let folderURL = try Disk.url(for: path.rawValue, in: .caches)
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in fileURLs where targetNames.contains(url.lastPathComponent) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            #if DEBUG
            print("Error deleting status files: \(error)")
            #endif
        }
    }

    /// Delete a specific file from disk (for documents, audio, etc.)
    func deleteFileFromDisk(fileName: String, ext: String, pathName: PathName) {
        do {
            let url = try Disk.url(for: pathName.rawValue + "/files/\(fileName).\(ext)", in: .documents)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                #if DEBUG
                print("Successfully deleted file: \(fileName).\(ext)")
                #endif
            }
        } catch {
            #if DEBUG
            print("Error deleting file: \(error)")
            #endif
        }
    }

}
