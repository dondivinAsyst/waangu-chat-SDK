//
//  DatabaseFileProtectionTests.swift
//  StorageKitTests
//
//  B29 — les satellites SQLite (`-wal`, `-shm`, `-journal`) et le dossier du
//  store reçoivent la même classe de protection que le store.
//

import XCTest
@testable import WaanguStorageKit

final class DatabaseFileProtectionTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "DatabaseFileProtectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func protection(_ path: String) throws -> FileProtectionType? {
        try FileManager.default.attributesOfItem(atPath: path)[.protectionKey] as? FileProtectionType
    }

    /// Runs anywhere: the paths the guard protects are SQLite's real names,
    /// plus the folder, so files SQLite creates later inherit the class.
    func test_protectionTargets_areTheFolderTheStoreAndSQLiteSatellites() {
        let store = URL(fileURLWithPath: "/db/StorageKit/Database/chat.sqlite")
        let targets = DatabaseEncryptionManager.protectionTargets(for: store, fileExists: { _ in true })
        for expected in ["/db/StorageKit/Database", store.path, store.path + "-wal", store.path + "-shm", store.path + "-journal"] {
            XCTAssertTrue(targets.contains(expected), expected)
        }
        XCTAssertFalse(targets.contains(store.path + ".wal"), "Not an SQLite file name")
        XCTAssertFalse(targets.contains(store.path + ".shm"), "Not an SQLite file name")
    }

    func test_absentSatellites_areSkipped_folderAndStoreAlwaysProtected() {
        let store = URL(fileURLWithPath: "/db/chat.sqlite")
        let targets = DatabaseEncryptionManager.protectionTargets(for: store, fileExists: { _ in false })
        XCTAssertEqual(targets, ["/db", store.path])
    }

    /// The iOS simulator does not implement data protection: the attribute reads
    /// back as nil there. On a device this checks the real protection class.
    func test_storeSatellitesAndDirectory_getCompleteUnlessOpen() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Data protection is not implemented on the simulator; run on a device.")
        #endif
        let store = directory.appending(path: "chat.sqlite")
        let satellites = DatabaseEncryptionManager.sqliteSatelliteSuffixes.map { store.path + $0 }
        for path in [store.path] + satellites {
            XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: Data("x".utf8)))
        }

        await DatabaseEncryptionManager.shared.applyFileProtection(to: store)

        for path in [store.path, directory.path] + satellites {
            XCTAssertEqual(try protection(path), .completeUnlessOpen, (path as NSString).lastPathComponent)
        }
    }

    /// SQLite's own names, not file extensions: `chat.sqlite-wal`, never `chat.sqlite.wal`.
    func test_satelliteNames_matchSQLite() {
        XCTAssertEqual(DatabaseEncryptionManager.sqliteSatelliteSuffixes, ["-wal", "-shm", "-journal"])
    }

    /// Provisional backup policy: the database folder stays out of backups, so a restored
    /// phone resyncs instead of inheriting another device's local state.
    func test_databaseFolder_isExcludedFromBackup() async throws {
        let store = directory.appending(path: "chat.sqlite")
        XCTAssertTrue(FileManager.default.createFile(atPath: store.path, contents: Data("x".utf8)))

        await DatabaseEncryptionManager.shared.applyFileProtection(to: store)

        let excluded = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, true)
    }
}
