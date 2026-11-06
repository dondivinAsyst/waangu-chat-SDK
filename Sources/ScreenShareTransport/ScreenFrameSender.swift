//
//  ScreenFrameSender.swift
//  ScreenShareTransport
//
//  Extension side. Connects to the app's socket, with retries: the system spawns
//  the broadcast extension and it routinely wins the race against the app.
//

import Foundation

public final class ScreenFrameSender {

    private let socketPath: String
    private var descriptor: Int32 = -1

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func connect(retries: Int = 20, retryDelay: TimeInterval = 0.1) throws {
        var lastError = ScreenShareSocketError.connectFailed(0)

        for attempt in 0...retries {
            let candidate = socket(AF_UNIX, SOCK_STREAM, 0)
            guard candidate >= 0 else {
                throw ScreenShareSocketError.socketCreationFailed(errno)
            }

            // Darwin has no MSG_NOSIGNAL — that is a Linux flag. Without
            // SO_NOSIGPIPE, writing to a socket whose peer has gone raises
            // SIGPIPE and kills the extension outright instead of returning
            // EPIPE we can handle.
            var noSigPipe: Int32 = 1
            setsockopt(
                candidate, SOL_SOCKET, SO_NOSIGPIPE,
                &noSigPipe, socklen_t(MemoryLayout<Int32>.size)
            )

            var address: sockaddr_un
            do {
                address = try ScreenShareSocketPath.makeAddress(for: socketPath)
            } catch {
                close(candidate)
                throw error
            }

            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(candidate, $0, ScreenShareSocketPath.addressLength)
                }
            }

            if result == 0 {
                descriptor = candidate
                return
            }

            lastError = .connectFailed(errno)
            close(candidate)
            if attempt < retries { Thread.sleep(forTimeInterval: retryDelay) }
        }

        throw lastError
    }

    public func send(_ frame: Data) throws {
        guard descriptor >= 0 else { throw ScreenShareSocketError.peerClosed }

        try frame.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < frame.count {
                // SIGPIPE is suppressed via SO_NOSIGPIPE at connect time, so a
                // dead app surfaces here as a -1 return with EPIPE.
                let written = Darwin.send(
                    descriptor,
                    base.advanced(by: offset),
                    frame.count - offset,
                    0
                )
                guard written > 0 else { throw ScreenShareSocketError.writeFailed(errno) }
                offset += written
            }
        }
    }

    public func disconnect() {
        guard descriptor >= 0 else { return }
        close(descriptor)
        descriptor = -1
    }
}
