import XCTest
@testable import WaanguFeatureChat

final class LocalMediaURLTests: XCTestCase {

    // MARK: - The bug this helper exists to prevent

    func test_urlStringInitializer_succeedsOnBarePathWithNoScheme() {
        // This is the whole bug. `URL(string:)` does NOT fail on a filesystem
        // path — a path-only string is a valid relative URL reference — so
        // `URL(string: path) ?? URL(fileURLWithPath: path)` never reaches its
        // fallback and yields a scheme-less URL nothing can read.
        let path = "/private/var/mobile/Media/DCIM/100APPLE/IMG_0042.MOV"

        let viaStringInit = URL(string: path)

        XCTAssertNotNil(viaStringInit, "URL(string:) unexpectedly failed; the ?? fallback would have worked")
        XCTAssertNil(viaStringInit?.scheme)
        XCTAssertFalse(viaStringInit?.isFileURL ?? true)
    }

    func test_dataContentsOf_throwsForSchemelessURL() throws {
        // Proves step 4 of the chain: the save silently threw and wrote nothing.
        let file = try makeTempFile(contents: "video-bytes")
        let schemeless = try XCTUnwrap(URL(string: file.path))

        XCTAssertThrowsError(try Data(contentsOf: schemeless))
    }

    // MARK: - resolve

    func test_resolve_barePathBecomesReadableFileURL() throws {
        let file = try makeTempFile(contents: "video-bytes")

        let resolved = try XCTUnwrap(LocalMediaURL.resolve(file.path))

        XCTAssertTrue(resolved.isFileURL)
        XCTAssertEqual(try Data(contentsOf: resolved), Data("video-bytes".utf8))
    }

    func test_resolve_preservesFileURLString() throws {
        let file = try makeTempFile(contents: "x")

        let resolved = try XCTUnwrap(LocalMediaURL.resolve(file.absoluteString))

        XCTAssertTrue(resolved.isFileURL)
        XCTAssertEqual(resolved.standardizedFileURL, file.standardizedFileURL)
    }

    func test_resolve_preservesRemoteURL() throws {
        let resolved = try XCTUnwrap(LocalMediaURL.resolve("https://example.com/clip.mp4"))

        XCTAssertEqual(resolved.scheme, "https")
        XCTAssertEqual(resolved.absoluteString, "https://example.com/clip.mp4")
    }

    func test_resolve_trimsSurroundingWhitespace() throws {
        let file = try makeTempFile(contents: "x")

        let resolved = try XCTUnwrap(LocalMediaURL.resolve("  \(file.path)\n"))

        XCTAssertTrue(resolved.isFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path))
    }

    func test_resolve_emptyOrWhitespaceIsNil() {
        XCTAssertNil(LocalMediaURL.resolve(""))
        XCTAssertNil(LocalMediaURL.resolve("   \n  "))
    }

    func test_resolve_relativePathWithoutLeadingSlashIsTreatedAsFile() throws {
        // Not expected in practice, but it must never produce a scheme-less URL.
        let resolved = try XCTUnwrap(LocalMediaURL.resolve("clip.mp4"))

        XCTAssertTrue(resolved.isFileURL)
    }

    func test_resolve_pathContainingSpaces() throws {
        // `URL(string:)` returns nil for unescaped spaces, so this would have
        // fallen through to the fileURLWithPath branch even in the old code —
        // it must keep working.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("media url tests \(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("my clip.mp4")
        try Data("x".utf8).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let resolved = try XCTUnwrap(LocalMediaURL.resolve(file.path))

        XCTAssertTrue(resolved.isFileURL)
        XCTAssertEqual(try Data(contentsOf: resolved), Data("x".utf8))
    }

    // MARK: - Helpers

    private func makeTempFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("localmediaurl-\(UUID().uuidString.lowercased()).mp4")
        try Data(contents.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
