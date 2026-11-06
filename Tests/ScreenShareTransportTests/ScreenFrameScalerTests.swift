import XCTest
import CoreVideo
@testable import WaanguScreenShareTransport

final class ScreenFrameScalerTests: XCTestCase {

    private let scaler = ScreenFrameScaler(maxLongEdge: 1280)

    private func makeNV12(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
            &buffer
        )
        return try XCTUnwrap(buffer, "CVPixelBufferCreate failed: \(status)")
    }

    func test_targetSize_clampsPortraitLongEdgeAndPreservesAspect() {
        let target = scaler.targetSize(for: CGSize(width: 1170, height: 2532))
        XCTAssertEqual(target.height, 1280)
        // 1170/2532 * 1280 = 591.4 → rounded to an even 592.
        XCTAssertEqual(target.width, 592)
    }

    func test_targetSize_clampsLandscapeLongEdge() {
        let target = scaler.targetSize(for: CGSize(width: 2532, height: 1170))
        XCTAssertEqual(target.width, 1280)
        XCTAssertEqual(target.height, 592)
    }

    func test_targetSize_neverUpscales() {
        let target = scaler.targetSize(for: CGSize(width: 640, height: 480))
        XCTAssertEqual(target, CGSize(width: 640, height: 480))
    }

    func test_targetSize_alwaysReturnsEvenDimensions() {
        // NV12 chroma is half-resolution; odd dimensions corrupt the plane.
        for height in [999, 1001, 1003, 2532] {
            let target = scaler.targetSize(for: CGSize(width: 501, height: CGFloat(height)))
            XCTAssertEqual(Int(target.width) % 2, 0, "width for height \(height)")
            XCTAssertEqual(Int(target.height) % 2, 0, "height for height \(height)")
        }
    }

    func test_scale_producesTargetSizedNV12Buffer() throws {
        let source = try makeNV12(width: 1170, height: 2532)
        let scaled = try scaler.scale(source)
        XCTAssertEqual(CVPixelBufferGetWidth(scaled), 592)
        XCTAssertEqual(CVPixelBufferGetHeight(scaled), 1280)
        XCTAssertEqual(
            CVPixelBufferGetPixelFormatType(scaled),
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        )
    }

    func test_scale_preservesAFlatImage() throws {
        // A uniformly-filled source must come back uniform. Catches plane
        // mix-ups and stride errors in the vImage buffers, which show up as
        // banding or garbage rather than as a wrong size.
        let source = try makeNV12(width: 1170, height: 2532)
        CVPixelBufferLockBaseAddress(source, [])
        let luma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(source, 0))
            .assumingMemoryBound(to: UInt8.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(source, 0)
        for row in 0..<2532 {
            memset(luma + row * lumaStride, 200, 1170)
        }
        CVPixelBufferUnlockBaseAddress(source, [])

        let scaled = try scaler.scale(source)

        CVPixelBufferLockBaseAddress(scaled, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(scaled, .readOnly) }
        let out = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(scaled, 0))
            .assumingMemoryBound(to: UInt8.self)
        let outStride = CVPixelBufferGetBytesPerRowOfPlane(scaled, 0)

        // Sample the interior; edge pixels can differ under interpolation.
        for row in stride(from: 4, to: 1276, by: 64) {
            for column in stride(from: 4, to: 588, by: 64) {
                XCTAssertEqual(
                    out[row * outStride + column], 200,
                    "row \(row) column \(column)"
                )
            }
        }
    }
}
