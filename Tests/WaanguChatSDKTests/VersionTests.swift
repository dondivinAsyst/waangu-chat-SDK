//
//  VersionTests.swift
//  WaanguChatSDKTests
//
//  SDK plan, step 1.2 — the version a host can read. The release script stamps it; these tests
//  guard what the script relies on.
//

import XCTest
@testable import WaanguChatSDK

final class WaanguChatVersionTests: XCTestCase {

    /// A development checkout never claims to be a release.
    func test_aDevelopmentBuild_reportsDevelopment_andIsNotARelease() {
        XCTAssertFalse(WaanguChatVersion.isRelease)
        XCTAssertEqual(WaanguChatVersion.current, WaanguChatVersion.development)
        XCTAssertEqual(WaanguChatVersion.development, "0.0.0-dev")
    }

    func test_theVersionIsAlwaysXYZ_orTheDevelopmentValue() {
        let shape = try! NSRegularExpression(pattern: #"^\d+\.\d+\.\d+(-dev)?$"#)
        let value = WaanguChatVersion.current
        XCTAssertNotNil(shape.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), value)
    }

    // MARK: What the release script relies on

    private func versionSource() throws -> String {
        // Tests/WaanguChatSDKTests/VersionTests.swift -> Sources/WaanguChatSDK/WaanguChatVersion.swift
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WaanguChatSDK/WaanguChatVersion.swift")
        return try String(contentsOf: source, encoding: .utf8)
    }

    /// The script refuses to publish unless there is exactly one marker.
    func test_theSourceHasExactlyOneMarker() throws {
        let text = try versionSource()
        XCTAssertEqual(text.components(separatedBy: "{{VERSION}}").count - 1, 1)
    }

    /// After the script's replacement, the constant holds the version and no marker is left.
    func test_stampingTheSource_putsTheVersionInTheConstant() throws {
        let stamped = try versionSource().replacingOccurrences(of: "{{VERSION}}", with: "9.8.7")

        XCTAssertTrue(stamped.contains(#"private static let stamped = "9.8.7""#))
        XCTAssertFalse(stamped.contains("{{VERSION}}"))
    }
}
