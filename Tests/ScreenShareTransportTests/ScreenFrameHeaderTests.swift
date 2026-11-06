import XCTest
@testable import WaanguScreenShareTransport

final class ScreenFrameHeaderTests: XCTestCase {

    private func makeHeader() -> ScreenFrameHeader {
        ScreenFrameHeader(
            width: 592,
            height: 1280,
            rotation: .quarter,
            lumaByteCount: 592 * 1280,
            chromaByteCount: 592 * 1280 / 2,
            timestampNanos: 1_234_567_890_123
        )
    }

    func test_encodedHeader_isExactlyThirtyTwoBytes() {
        XCTAssertEqual(makeHeader().encoded().count, ScreenFrameHeader.byteCount)
        XCTAssertEqual(ScreenFrameHeader.byteCount, 32)
    }

    func test_roundTrip_preservesEveryField() throws {
        let original = makeHeader()
        let decoded = try ScreenFrameHeader.decode(original.encoded())
        XCTAssertEqual(decoded, original)
    }

    func test_payloadByteCount_isLumaPlusChroma() {
        let header = makeHeader()
        XCTAssertEqual(header.payloadByteCount, 592 * 1280 + 592 * 1280 / 2)
    }

    func test_decode_rejectsTruncatedBuffer() {
        let short = makeHeader().encoded().dropLast()
        XCTAssertThrowsError(try ScreenFrameHeader.decode(Data(short))) { error in
            XCTAssertEqual(error as? ScreenFrameProtocolError, .truncated)
        }
    }

    func test_decode_rejectsBadMagic() {
        var bytes = makeHeader().encoded()
        bytes[0] = 0x00
        XCTAssertThrowsError(try ScreenFrameHeader.decode(bytes)) { error in
            XCTAssertEqual(error as? ScreenFrameProtocolError, .badMagic)
        }
    }

    func test_decode_rejectsUnknownVersion() {
        var bytes = makeHeader().encoded()
        bytes[4] = 99
        XCTAssertThrowsError(try ScreenFrameHeader.decode(bytes)) { error in
            XCTAssertEqual(error as? ScreenFrameProtocolError, .unsupportedVersion(99))
        }
    }

    func test_decode_rejectsBadRotation() {
        var bytes = makeHeader().encoded()
        bytes[5] = 7
        XCTAssertThrowsError(try ScreenFrameHeader.decode(bytes)) { error in
            XCTAssertEqual(error as? ScreenFrameProtocolError, .badRotation(7))
        }
    }

    func test_rotationDegrees() {
        XCTAssertEqual(ScreenFrameRotation.none.degrees, 0)
        XCTAssertEqual(ScreenFrameRotation.quarter.degrees, 90)
        XCTAssertEqual(ScreenFrameRotation.half.degrees, 180)
        XCTAssertEqual(ScreenFrameRotation.threeQuarter.degrees, 270)
    }
}
