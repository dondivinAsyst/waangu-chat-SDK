import XCTest
import CoreVideo
import WaanguScreenShareTransport
@testable import WaanguFeatureChat

final class ScreenShareFrameBridgeTests: XCTestCase {

    private var socketPath: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        socketPath = "/tmp/ssb-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(4)).sock"
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: socketPath)
        try super.tearDownWithError()
    }

    private func makeFrame(rotation: ScreenFrameRotation, timestampNanos: UInt64) throws -> Data {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 32,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &buffer
        )
        let pixelBuffer = try XCTUnwrap(buffer)
        return try ScreenFramePacker.pack(
            pixelBuffer, rotation: rotation, timestampNanos: timestampNanos
        )
    }

    /// The one that matters: a frame written by the sender must arrive at the
    /// sink with rotation translated from quarter-turns to degrees and the
    /// timestamp intact. Everything between is real — socket, header, planes.
    func test_frameFromSenderReachesSinkWithRotationInDegrees() throws {
        let delivered = expectation(description: "frame reached the sink")
        let lock = NSLock()
        var received: [(rotation: Int, timestamp: UInt64)] = []

        let bridge = ScreenShareFrameBridge(
            resolveSocketPath: { [socketPath] in socketPath! },
            submitFrame: { _, rotation, timestamp in
                lock.lock()
                received.append((rotation, timestamp))
                lock.unlock()
                delivered.fulfill()
            }
        )
        try bridge.start()
        defer { bridge.stop() }

        let sender = ScreenFrameSender(socketPath: socketPath)
        try sender.connect()
        try sender.send(try makeFrame(rotation: .threeQuarter, timestampNanos: 7_000))
        defer { sender.disconnect() }

        wait(for: [delivered], timeout: 5)

        lock.lock()
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.rotation, 270, "quarter-turns must become degrees")
        XCTAssertEqual(received.first?.timestamp, 7_000)
        lock.unlock()
    }

    func test_onFirstFrameFiresOnceNotPerFrame() throws {
        let framesIn = expectation(description: "three frames delivered")
        framesIn.expectedFulfillmentCount = 3

        let lock = NSLock()
        var firstFrameCount = 0

        let bridge = ScreenShareFrameBridge(
            resolveSocketPath: { [socketPath] in socketPath! },
            submitFrame: { _, _, _ in framesIn.fulfill() }
        )
        bridge.onFirstFrame = {
            lock.lock()
            firstFrameCount += 1
            lock.unlock()
        }
        try bridge.start()
        defer { bridge.stop() }

        let sender = ScreenFrameSender(socketPath: socketPath)
        try sender.connect()
        for index in 0..<3 {
            try sender.send(try makeFrame(rotation: .none, timestampNanos: UInt64(index)))
        }
        defer { sender.disconnect() }

        wait(for: [framesIn], timeout: 5)

        lock.lock()
        XCTAssertEqual(firstFrameCount, 1, "onFirstFrame is the broadcast-started signal")
        lock.unlock()
    }

    func test_startTwiceDoesNotBindTheSocketTwice() throws {
        let bridge = ScreenShareFrameBridge(
            resolveSocketPath: { [socketPath] in socketPath! },
            submitFrame: { _, _, _ in }
        )
        try bridge.start()
        defer { bridge.stop() }
        // A second bind on the same path would throw EADDRINUSE.
        XCTAssertNoThrow(try bridge.start())
    }

    func test_stopWithoutStartIsSafe() {
        let bridge = ScreenShareFrameBridge(
            resolveSocketPath: { [socketPath] in socketPath! },
            submitFrame: { _, _, _ in }
        )
        XCTAssertNoThrow(bridge.stop())
    }

    func test_startPropagatesSocketPathFailure() {
        struct Boom: Error {}
        let bridge = ScreenShareFrameBridge(
            resolveSocketPath: { throw Boom() },
            submitFrame: { _, _, _ in }
        )
        // A missing App Group must surface, not be swallowed into a bridge that
        // silently never receives anything.
        XCTAssertThrowsError(try bridge.start())
    }
}
