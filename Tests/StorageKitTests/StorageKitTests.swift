//
//  StorageKitTests.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import XCTest
@testable import WaanguStorageKit
import WaanguCoreKit

final class StorageKitTests: XCTestCase {

    // MARK: - PreferenceStore

    func testPreferenceStoreRoundTrip() {
        let store = PreferenceStore(suiteName: "com.storagekit.test.\(UUID().uuidString)")

        store.set("dark", forKey: "theme")
        XCTAssertEqual(store.string(forKey: "theme"), "dark")

        store.set(42, forKey: "count")
        XCTAssertEqual(store.int(forKey: "count"), 42)

        store.set(true, forKey: "flag")
        XCTAssertTrue(store.bool(forKey: "flag"))

        XCTAssertTrue(store.contains(key: "theme"))
        XCTAssertFalse(store.contains(key: "nonexistent"))
    }

    func testPreferenceStoreDefaultValues() {
        let store = PreferenceStore(suiteName: "com.storagekit.test.\(UUID().uuidString)")

        XCTAssertEqual(store.bool(forKey: "missing", default: true), true)
        XCTAssertEqual(store.int(forKey: "missing", default: 99), 99)
        XCTAssertEqual(store.double(forKey: "missing", default: 3.14), 3.14)
        XCTAssertNil(store.string(forKey: "missing"))
    }

    func testPreferenceStoreCodable() throws {
        let store = PreferenceStore(suiteName: "com.storagekit.test.\(UUID().uuidString)")

        struct Config: Codable, Sendable, Equatable {
            let name: String
            let version: Int
        }

        let config = Config(name: "test", version: 2)
        try store.setCodable(config, forKey: "config")
        let loaded: Config? = try store.getCodable(Config.self, forKey: "config")
        XCTAssertEqual(loaded, config)
    }

    func testPreferenceStoreRemove() {
        let store = PreferenceStore(suiteName: "com.storagekit.test.\(UUID().uuidString)")

        store.set("value", forKey: "key")
        XCTAssertNotNil(store.string(forKey: "key"))

        store.remove(forKey: "key")
        XCTAssertNil(store.string(forKey: "key"))
    }

    func testPreferenceStoreRemoveAll() {
        let store = PreferenceStore(suiteName: "com.storagekit.test.\(UUID().uuidString)")

        store.set("a", forKey: "k1")
        store.set("b", forKey: "k2")
        store.removeAll(forKeys: ["k1", "k2"])
        XCTAssertNil(store.string(forKey: "k1"))
        XCTAssertNil(store.string(forKey: "k2"))
    }

    // MARK: - TemporaryFileStore

    func testTemporaryFileStoreWriteAndRead() async throws {
        let store = TemporaryFileStore(subdirectory: "test-\(UUID().uuidString)")
        let data = "hello".data(using: .utf8)!

        let url = try await store.write(data: data, fileName: "test.txt")
        XCTAssertTrue(url.path.contains("test.txt"))

        let loaded = try await store.read(fileName: "test.txt")
        XCTAssertEqual(loaded, data)

        try await store.clearAll()
    }

    func testTemporaryFileStoreDeleteAndExists() async throws {
        let store = TemporaryFileStore(subdirectory: "test-\(UUID().uuidString)")
        let data = Data([0x01, 0x02])

        try await store.write(data: data, fileName: "temp.bin")
        let existsAfterWrite = await store.exists(fileName: "temp.bin")
        XCTAssertTrue(existsAfterWrite)

        try await store.delete(fileName: "temp.bin")
        let existsAfterDelete = await store.exists(fileName: "temp.bin")
        XCTAssertFalse(existsAfterDelete)
    }

    func testTemporaryFileStoreReadNotFound() async {
        let store = TemporaryFileStore(subdirectory: "test-\(UUID().uuidString)")
        do {
            _ = try await store.read(fileName: "nope.txt")
            XCTFail("Expected FileStoreError.fileNotFound")
        } catch is FileStoreError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTemporaryFileStoreListFiles() async throws {
        let store = TemporaryFileStore(subdirectory: "test-\(UUID().uuidString)")

        try await store.write(data: Data([0x01]), fileName: "a.txt")
        try await store.write(data: Data([0x02]), fileName: "b.txt")

        let files = try await store.listFiles()
        XCTAssertTrue(files.contains("a.txt"))
        XCTAssertTrue(files.contains("b.txt"))

        try await store.clearAll()
    }

    func testUniqueFileName() async {
        let store = TemporaryFileStore()
        let name = await store.uniqueFileName(extension: "jpg")
        XCTAssertTrue(name.hasSuffix(".jpg"))
        XCTAssertEqual(name.count, 36 + 1 + 3) // UUID + "." + "jpg"
    }

    // MARK: - KeychainError

    func testKeychainErrorDescriptions() {
        let secError = KeychainError.securityError(status: errSecDuplicateItem)
        XCTAssertNotNil(secError.errorDescription)

        let encError = KeychainError.encodingFailed
        XCTAssertEqual(encError.errorDescription, "Failed to encode value to UTF-8 data")

        let decError = KeychainError.decodingFailed(type: "Token")
        XCTAssertEqual(decError.errorDescription, "Failed to decode Keychain data to Token")
    }

    // MARK: - FileStoreError

    func testFileStoreErrorDescriptions() {
        XCTAssertNotNil(FileStoreError.writeFailed(fileName: "f", underlying: "err").errorDescription)
        XCTAssertNotNil(FileStoreError.readFailed(fileName: "f", underlying: "err").errorDescription)
        XCTAssertNotNil(FileStoreError.fileNotFound(fileName: "f").errorDescription)
    }
}
