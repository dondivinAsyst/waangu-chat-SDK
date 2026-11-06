//
//  TemporaryFileStore.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//
import WaanguCoreKit
import Foundation

/// Gestionnaire de fichiers temporaires thread-safe.
///
/// Toutes les opérations passent par l'actor pour garantir la cohérence.
/// Les erreurs sont typées (`FileStoreError`) au lieu de retourner `nil`.
///
/// Usage :
/// ```swift
/// let store = TemporaryFileStore()
/// let url = try await store.write(data: imageData, fileName: "avatar.jpg")
/// let loaded = try await store.read(fileName: "avatar.jpg")
/// try await store.delete(fileName: "avatar.jpg")
/// ```
public actor TemporaryFileStore: TemporaryFileStoreProtocol {

    private let fileManager: FileManager
    private let baseDirectory: URL

    /// - Parameter subdirectory: Sous-dossier optionnel dans `tmp/` pour isoler les fichiers.
    ///                           Ex: `"uploads"` → `tmp/uploads/`.
    public init(subdirectory: String? = nil) {
        self.fileManager = .default
        var base = FileManager.default.temporaryDirectory
        if let subdirectory {
            base = base.appendingPathComponent(subdirectory, isDirectory: true)
        }
        self.baseDirectory = base
    }

    // MARK: - Write

    @discardableResult
    public func write(data: Data, fileName: String) async throws -> URL {
        try ensureDirectoryExists()
        let url = baseDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw FileStoreError.writeFailed(fileName: fileName, underlying: error.localizedDescription)
        }
    }

    // MARK: - Read

    public func read(fileName: String) async throws -> Data {
        let url = baseDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileStoreError.fileNotFound(fileName: fileName)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw FileStoreError.readFailed(fileName: fileName, underlying: error.localizedDescription)
        }
    }

    // MARK: - Delete

    public func delete(fileName: String) async throws {
        let url = baseDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw FileStoreError.deleteFailed(fileName: fileName, underlying: error.localizedDescription)
        }
    }

    // MARK: - Query

    public func exists(fileName: String) async -> Bool {
        fileManager.fileExists(atPath: baseDirectory.appendingPathComponent(fileName).path)
    }

    public func url(for fileName: String) async -> URL {
        baseDirectory.appendingPathComponent(fileName)
    }

    // MARK: - Bulk Operations

    public func clearAll() async throws {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: nil,
                options: []
            )
            for url in contents {
                try fileManager.removeItem(at: url)
            }
        } catch {
            throw FileStoreError.directoryCleanupFailed(underlying: error.localizedDescription)
        }
    }

    public func listFiles() async throws -> [String] {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return [] }
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return contents.map(\.lastPathComponent)
        } catch {
            throw FileStoreError.directoryCleanupFailed(underlying: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    public func uniqueFileName(extension ext: String) async -> String {
        "\(UUID().uuidString).\(ext)"
    }

    private func ensureDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
}
