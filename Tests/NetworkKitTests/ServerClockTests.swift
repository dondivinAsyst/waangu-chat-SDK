//
//  ServerClockTests.swift
//  NetworkKitTests
//

import XCTest
@testable import WaanguNetworkKit

/// A quote expires on the server's clock. `ServerClock` learns the gap between the
/// phone and the server from the `Date` header of a response.
final class ServerClockTests: XCTestCase {

    private func response(date: String?) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: 200, httpVersion: nil,
                        headerFields: date.map { ["Date": $0] })!
    }

    func test_withoutAResponse_nowIsTheDeviceClock() {
        let clock = ServerClock()
        XCTAssertEqual(clock.now.timeIntervalSinceNow, 0, accuracy: 1)
    }

    func test_parsesTheHTTPDateFormat() {
        let date = ServerClock.parse("Tue, 10 Nov 2026 09:30:00 GMT")
        XCTAssertEqual(date, Date(timeIntervalSince1970: 1_794_303_000))
    }

    func test_aServerAheadOfThePhone_movesNowForward() {
        let clock = ServerClock()
        let received = Date(timeIntervalSince1970: 1_794_303_000)
        // The server says 09:31:00 when the phone read 09:30:00 — the phone is 60 s behind.
        clock.observe(response: response(date: "Tue, 10 Nov 2026 09:31:00 GMT"), receivedAt: received)
        XCTAssertEqual(clock.adjusted(received).timeIntervalSince(received), 60, accuracy: 0.001)
    }

    func test_aServerBehindThePhone_movesNowBack() {
        let clock = ServerClock()
        let received = Date(timeIntervalSince1970: 1_794_303_000)
        clock.observe(response: response(date: "Tue, 10 Nov 2026 09:29:00 GMT"), receivedAt: received)
        XCTAssertEqual(clock.adjusted(received).timeIntervalSince(received), -60, accuracy: 0.001)
    }

    func test_aMissingOrMalformedHeader_leavesTheOffsetAlone() {
        let clock = ServerClock()
        let received = Date(timeIntervalSince1970: 1_794_303_000)
        clock.observe(response: response(date: "Tue, 10 Nov 2026 09:31:00 GMT"), receivedAt: received)
        clock.observe(response: response(date: nil), receivedAt: received)
        clock.observe(response: response(date: "not a date"), receivedAt: received)
        XCTAssertEqual(clock.adjusted(received).timeIntervalSince(received), 60, accuracy: 0.001)
    }
}
