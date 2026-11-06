//
//  ChatOutboxInspecting.swift
//  FeatureChat
//
//  Read side of the outbox. `ChatOutboxEnqueuing` writes, this one only looks —
//  keeping the diagnostics screen incapable of sending, retrying, or clearing.
//

import Foundation

public protocol ChatOutboxInspecting: Sendable {
    /// Both outbound queues as they stand right now.
    ///
    /// Throws rather than returning an empty snapshot when the store cannot be
    /// read: on a diagnostics screen, "unreadable" and "empty" must not look alike.
    func snapshot() async throws -> ChatOutboxSnapshot
}
