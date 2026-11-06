import XCTest
import CoreVideo
@testable import WaanguScreenShareTransport

final class ScreenShareSocketPathTests: XCTestCase {

    func test_socketPathInContainer_appendsShortFilename() throws {
        let container = URL(fileURLWithPath: "/tmp/group.container", isDirectory: true)
        let path = try ScreenShareSocketPath.socketPath(inContainer: container)
        XCTAssertEqual(path, "/tmp/group.container/ss.sock")
    }

    func test_socketPathInContainer_rejectsPathLongerThanSunPath() {
        // sockaddr_un.sun_path is 104 bytes on Darwin. A real App Group container
        // already burns ~84 of them, so this guard is not theoretical — and bind()
        // failing on a silently truncated path is miserable to diagnose on device.
        let container = URL(
            fileURLWithPath: "/" + String(repeating: "a", count: 120),
            isDirectory: true
        )
        XCTAssertThrowsError(try ScreenShareSocketPath.socketPath(inContainer: container)) { error in
            guard case ScreenShareSocketError.pathTooLong = error else {
                return XCTFail("expected pathTooLong, got \(error)")
            }
        }
    }

    func test_realAppGroupContainerPathWouldFitIfPresent() throws {
        // Documents the budget rather than the environment: a typical container
        // path plus "ss.sock" must clear 104 bytes.
        let typical = URL(
            fileURLWithPath:
                "/private/var/mobile/Containers/Shared/AppGroup/"
                + "12345678-1234-1234-1234-123456789012",
            isDirectory: true
        )
        let path = try ScreenShareSocketPath.socketPath(inContainer: typical)
        XCTAssertLessThan(path.utf8.count, ScreenShareSocketPath.maxLength)
    }
}

final class ScreenFrameSocketTests: XCTestCase {

    private var socketPath: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Short temp path — a long one would trip the sun_path guard we are
        // deliberately enforcing.
        socketPath = "/tmp/ss-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(4)).sock"
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: socketPath)
        try super.tearDownWithError()
    }

    private func makeFrame(width: Int, height: Int, timestampNanos: UInt64) throws -> Data {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &buffer
        )
        let pixelBuffer = try XCTUnwrap(buffer)
        return try ScreenFramePacker.pack(
            pixelBuffer, rotation: .quarter, timestampNanos: timestampNanos
        )
    }

    func test_senderDeliversFramesToReceiverInOrder() throws {
        let received = expectation(description: "three frames received")
        received.expectedFulfillmentCount = 3

        let lock = NSLock()
        var timestamps: [UInt64] = []

        let receiver = ScreenFrameReceiver(socketPath: socketPath)
        try receiver.start { header, pixelBuffer in
            XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), 64)
            XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), 32)
            XCTAssertEqual(header.rotation, .quarter)
            lock.lock()
            timestamps.append(header.timestampNanos)
            lock.unlock()
            received.fulfill()
        }
        defer { receiver.stop() }

        let sender = ScreenFrameSender(socketPath: socketPath)
        try sender.connect()
        for index in 0..<3 {
            try sender.send(try makeFrame(width: 64, height: 32, timestampNanos: UInt64(index)))
        }

        wait(for: [received], timeout: 5)
        sender.disconnect()

        lock.lock()
        XCTAssertEqual(timestamps, [0, 1, 2])
        lock.unlock()
    }

    func test_senderRetriesUntilReceiverIsListening() throws {
        let frameArrived = expectation(description: "frame arrived")

        let receiver = ScreenFrameReceiver(socketPath: socketPath)
        // The extension is spawned by the system and routinely beats the app to
        // the socket. Connecting must survive that.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [socketPath] in
            do {
                try receiver.start { _, _ in frameArrived.fulfill() }
            } catch {
                XCTFail("receiver failed to start on \(socketPath!): \(error)")
            }
        }
        defer { receiver.stop() }

        let sender = ScreenFrameSender(socketPath: socketPath)
        try sender.connect(retries: 100, retryDelay: 0.05)
        try sender.send(try makeFrame(width: 64, height: 32, timestampNanos: 0))

        wait(for: [frameArrived], timeout: 10)
        sender.disconnect()
    }

    func test_connectFailsAfterRetriesExhausted() {
        let sender = ScreenFrameSender(socketPath: "/tmp/ss-nobody-listening-\(UUID().uuidString.prefix(6)).sock")
        XCTAssertThrowsError(try sender.connect(retries: 2, retryDelay: 0.01))
    }

    func test_sendAfterPeerHangsUpFailsRatherThanKillingTheProcess() throws {
        // Without SO_NOSIGPIPE this raises SIGPIPE and takes the extension down
        // instead of returning EPIPE. MSG_NOSIGNAL does not exist on Darwin.
        let receiver = ScreenFrameReceiver(socketPath: socketPath)
        try receiver.start { _, _ in }

        let sender = ScreenFrameSender(socketPath: socketPath)
        try sender.connect()
        receiver.stop()

        // The first write may land in the socket buffer; keep writing until the
        // close is observed. Reaching the end of the loop without throwing means
        // the failure was not surfaced.
        var threw = false
        for index in 0..<200 where !threw {
            do {
                try sender.send(try makeFrame(width: 64, height: 32, timestampNanos: UInt64(index)))
            } catch {
                threw = true
            }
        }
        sender.disconnect()
        XCTAssertTrue(threw, "writing to a closed peer must surface an error")
    }
}
