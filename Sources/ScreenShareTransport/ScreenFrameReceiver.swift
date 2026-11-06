//
//  ScreenFrameReceiver.swift
//  ScreenShareTransport
//
//  Main-app side. Listens on the App Group socket and hands decoded frames up.
//  The app is the server because it outlives the extension: a CallKit call keeps
//  it alive, while the broadcast extension is spawned and killed by the system.
//

import Foundation
import CoreVideo

public final class ScreenFrameReceiver {

    private let socketPath: String
    private let queue = DispatchQueue(label: "com.waangu.screenshare.receiver")
    private let lock = NSLock()
    private var listenerDescriptor: Int32 = -1
    private var _isRunning = false

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func start(
        onFrame: @escaping (ScreenFrameHeader, CVPixelBuffer) -> Void
    ) throws {
        // A stale socket file from a crashed run makes bind fail with EADDRINUSE.
        try? FileManager.default.removeItem(atPath: socketPath)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw ScreenShareSocketError.socketCreationFailed(errno)
        }

        var address: sockaddr_un
        do {
            address = try ScreenShareSocketPath.makeAddress(for: socketPath)
        } catch {
            close(descriptor)
            throw error
        }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, ScreenShareSocketPath.addressLength)
            }
        }
        guard bound == 0 else {
            let code = errno
            close(descriptor)
            throw ScreenShareSocketError.bindFailed(code)
        }

        guard listen(descriptor, 1) == 0 else {
            let code = errno
            close(descriptor)
            throw ScreenShareSocketError.listenFailed(code)
        }

        lock.lock()
        listenerDescriptor = descriptor
        _isRunning = true
        lock.unlock()

        queue.async { [weak self] in self?.acceptLoop(onFrame: onFrame) }
    }

    public func stop() {
        lock.lock()
        _isRunning = false
        let descriptor = listenerDescriptor
        listenerDescriptor = -1
        lock.unlock()

        // Closing the listener makes the blocked accept() return, which is how
        // the loop learns to exit.
        if descriptor >= 0 { close(descriptor) }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    // MARK: - Reading

    private func acceptLoop(onFrame: @escaping (ScreenFrameHeader, CVPixelBuffer) -> Void) {
        while isRunning {
            lock.lock()
            let listener = listenerDescriptor
            lock.unlock()
            guard listener >= 0 else { return }

            let connection = accept(listener, nil, nil)
            guard connection >= 0 else {
                guard isRunning else { return }
                continue
            }
            readLoop(connection: connection, onFrame: onFrame)
            close(connection)
        }
    }

    private func readLoop(
        connection: Int32,
        onFrame: @escaping (ScreenFrameHeader, CVPixelBuffer) -> Void
    ) {
        while isRunning {
            do {
                let headerBytes = try readExactly(ScreenFrameHeader.byteCount, from: connection)
                let header = try ScreenFrameHeader.decode(headerBytes)
                let payload = try readExactly(header.payloadByteCount, from: connection)
                let pixelBuffer = try ScreenFramePacker.unpack(header: header, payload: payload)
                onFrame(header, pixelBuffer)
            } catch ScreenShareSocketError.peerClosed {
                // Broadcast finished or the extension was killed. Expected —
                // fall back to accept() and wait for the next broadcast.
                return
            } catch {
                // A corrupt frame desynchronises the stream; there is no
                // resynchronisation point, so drop the connection and rebuild.
                NSLog("[ScreenShare] receiver dropping connection: \(error)")
                return
            }
        }
    }

    private func readExactly(_ count: Int, from connection: Int32) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let read = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return recv(connection, base.advanced(by: offset), count - offset, 0)
            }
            guard read > 0 else { throw ScreenShareSocketError.peerClosed }
            offset += read
        }
        return Data(buffer)
    }
}
