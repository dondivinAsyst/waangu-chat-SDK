//
//  DebugLog.swift
//  CoreKit
//
//  Cheap synchronous logging for code paths that run per event.
//

import Foundation
import os

/// Logs a message from a hot code path, compiled out of release builds.
///
/// Use this instead of `print` anywhere the call can repeat — per inbound
/// realtime message, per synced row, per signaling event, per list update.
///
/// `print` writes to stdout. In the simulator that is a local pipe and costs
/// almost nothing, but on a physical device with Xcode attached every line
/// travels over the debug connection, and the write blocks the calling thread
/// when Xcode cannot drain it fast enough. A burst of them registers as a
/// main-thread hang — the same stall that looks like the app freezing.
/// `Logger` writes to the unified logging system, which applies no such
/// back-pressure and discards the message outright when nothing is listening.
///
/// The message is an autoclosure, so building the string costs nothing in
/// release where the call has no body.
///
/// For structured or persisted logging, use ``AppLogger`` instead — this is
/// only for developer breadcrumbs.
public func debugLog(
    _ message: @autoclosure () -> String,
    category: String = "app"
) {
    #if DEBUG
    // Evaluated into a local first: `Logger`'s interpolation captures its
    // argument escapingly, which a non-escaping autoclosure cannot satisfy.
    let text = message()
    DebugLogChannel.shared.logger(for: category).debug("\(text, privacy: .public)")
    #endif
}

#if DEBUG
/// Caches one `Logger` per category. Creating a logger is not free, and these
/// call sites repeat.
private final class DebugLogChannel: @unchecked Sendable {

    static let shared = DebugLogChannel()

    private let lock = NSLock()
    private var loggers: [String: Logger] = [:]

    private init() {}

    func logger(for category: String) -> Logger {
        lock.lock()
        defer { lock.unlock() }

        if let existing = loggers[category] { return existing }
        let created = Logger(subsystem: "com.waangu.app", category: category)
        loggers[category] = created
        return created
    }
}
#endif
