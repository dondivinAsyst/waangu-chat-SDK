import XCTest
import CoreVideo
@testable import WaanguScreenShareTransport

final class ScreenFramePackerTests: XCTestCase {

    /// Builds an NV12 buffer whose luma is a horizontal ramp and whose chroma is
    /// a constant, so padding bugs show up as a shifted ramp rather than noise.
    private func makeNV12(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
            &buffer
        )
        let pixelBuffer = try XCTUnwrap(buffer, "CVPixelBufferCreate failed: \(status)")

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let luma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0))
            .assumingMemoryBound(to: UInt8.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        for row in 0..<height {
            for column in 0..<width {
                luma[row * lumaStride + column] = UInt8(column % 256)
            }
        }

        let chroma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1))
            .assumingMemoryBound(to: UInt8.self)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        for row in 0..<(height / 2) {
            for column in 0..<width {
                chroma[row * chromaStride + column] = 128
            }
        }
        return pixelBuffer
    }

    func test_pack_producesHeaderPlusTightlyPackedPlanes() throws {
        let source = try makeNV12(width: 64, height: 32)
        let packed = try ScreenFramePacker.pack(source, rotation: .quarter, timestampNanos: 42)

        let header = try ScreenFrameHeader.decode(packed)
        XCTAssertEqual(header.width, 64)
        XCTAssertEqual(header.height, 32)
        XCTAssertEqual(header.rotation, .quarter)
        XCTAssertEqual(header.timestampNanos, 42)
        XCTAssertEqual(header.lumaByteCount, 64 * 32)
        XCTAssertEqual(header.chromaByteCount, 64 * 16)
        XCTAssertEqual(packed.count, ScreenFrameHeader.byteCount + 64 * 32 + 64 * 16)
    }

    /// 100 rather than 64 on purpose.
    ///
    /// CoreVideo aligns rows, so a 64-wide buffer comes back with
    /// `bytesPerRow == width` — no padding, and a packer that confuses the two
    /// strides passes anyway. 100 forces real padding, which is the only case
    /// that discriminates. The assertion below fails loudly if a future platform
    /// stops padding here, rather than letting this quietly stop testing anything.
    private static let paddedWidth = 100

    func test_roundTrip_preservesLumaRampAcrossPaddedRows() throws {
        let width = Self.paddedWidth
        let source = try makeNV12(width: width, height: 32)
        let packed = try ScreenFramePacker.pack(source, rotation: .none, timestampNanos: 0)
        let header = try ScreenFrameHeader.decode(packed)
        let payload = packed.dropFirst(ScreenFrameHeader.byteCount)

        let restored = try ScreenFramePacker.unpack(header: header, payload: Data(payload))

        XCTAssertEqual(CVPixelBufferGetWidth(restored), width)
        XCTAssertEqual(CVPixelBufferGetHeight(restored), 32)
        XCTAssertEqual(
            CVPixelBufferGetPixelFormatType(restored),
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        )

        CVPixelBufferLockBaseAddress(restored, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(restored, .readOnly) }
        let luma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(restored, 0))
            .assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(restored, 0)

        XCTAssertGreaterThan(
            stride, width,
            "buffer is unpadded, so this test cannot detect a stride confusion"
        )

        // Every row must read 0,1,2,… — a stride bug skews later rows most.
        for row in 0..<32 {
            for column in 0..<width {
                XCTAssertEqual(
                    luma[row * stride + column],
                    UInt8(column % 256),
                    "row \(row) column \(column)"
                )
            }
        }
    }

    func test_unpack_rejectsPayloadOfWrongSize() throws {
        let header = ScreenFrameHeader(
            width: 64, height: 32, rotation: .none,
            lumaByteCount: 64 * 32, chromaByteCount: 64 * 16, timestampNanos: 0
        )
        XCTAssertThrowsError(
            try ScreenFramePacker.unpack(header: header, payload: Data(count: 10))
        ) { error in
            XCTAssertEqual(
                error as? ScreenFramePackerError,
                .payloadSizeMismatch(expected: 64 * 32 + 64 * 16, actual: 10)
            )
        }
    }

    func test_pack_rejectsNonNV12Buffer() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer)
        let bgra = try XCTUnwrap(buffer)
        XCTAssertThrowsError(
            try ScreenFramePacker.pack(bgra, rotation: .none, timestampNanos: 0)
        ) { error in
            XCTAssertEqual(
                error as? ScreenFramePackerError,
                .unsupportedPixelFormat(kCVPixelFormatType_32BGRA)
            )
        }
    }
}
