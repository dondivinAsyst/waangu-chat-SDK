//
//  ScreenShareSocketPath.swift
//  ScreenShareTransport
//

import Foundation

public enum ScreenShareSocketError: Error, Equatable {
    case appGroupUnavailable
    case pathTooLong(Int)
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case writeFailed(Int32)
    case peerClosed
}

public enum ScreenShareSocketPath {

    public static let appGroupIdentifier = "group.com.waangu.chat"

    /// `sockaddr_un.sun_path` is 104 bytes on Darwin.
    public static let maxLength = 104

    /// Short on purpose: the App Group container path already burns ~84 of the
    /// 104 available bytes.
    public static let filename = "ss.sock"

    public static func resolve(
        appGroupIdentifier: String = appGroupIdentifier
    ) throws -> String {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw ScreenShareSocketError.appGroupUnavailable
        }
        return try socketPath(inContainer: container)
    }

    /// Split out from `resolve` so the length guard is testable without an App
    /// Group — a bogus group id fails earlier, at `containerURL`, and would
    /// never reach this check.
    public static func socketPath(inContainer container: URL) throws -> String {
        let path = container.appendingPathComponent(filename).path
        guard path.utf8.count < maxLength else {
            throw ScreenShareSocketError.pathTooLong(path.utf8.count)
        }
        return path
    }
}

// MARK: - sockaddr_un helpers

extension ScreenShareSocketPath {

    /// Fills a `sockaddr_un` with `path`, throwing rather than letting `strcpy`
    /// truncate — a truncated socket path fails at bind/connect with an error
    /// that points nowhere near the real cause.
    static func makeAddress(for path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            throw ScreenShareSocketError.pathTooLong(path.utf8.count)
        }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = path.withCString { strcpy(destination, $0) }
            }
        }
        return address
    }

    static let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
}
