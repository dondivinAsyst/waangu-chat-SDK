//
//  ChatOutboxMaintaining.swift
//  FeatureChat
//
//  Settling and replaying queued actions.
//
//  A row leaves the outbox when the server acknowledges it — not when the MQTT
//  publish returns, which only proves the broker accepted the bytes. Actions the
//  server never acknowledges are replayed on reconnect until their attempts run
//  out, so nothing is resent forever.
//
//  `ChatOutboxEnqueuing` writes, `ChatOutboxInspecting` reads, this one settles.
//

import Foundation

// MARK: - ChatOutboxSettlement

public enum ChatOutboxSettlement: Sendable {
    /// The server confirmed the action. The row is cleared.
    case acknowledged
    /// The server rejected it. The row is kept, marked failed, carrying the reason.
    case rejected(reason: String)
}

// MARK: - ChatOutboxMaintaining

public protocol ChatOutboxMaintaining: Sendable {

    /// Settles every queued action of `actionType` aimed at `reference` — a
    /// `codeMessage` for message actions, a story id for story ones.
    ///
    /// - Returns: how many rows it settled. Zero means the acknowledgement
    ///   arrived for something this device never queued.
    @discardableResult
    func settle(
        _ actionType: ChatOutboxItemActionType,
        reference: String,
        as settlement: ChatOutboxSettlement
    ) async -> Int

    /// Actions still unacknowledged past `age`, oldest first.
    func pending(olderThan age: TimeInterval) async -> [ChatOutboxItem]

    /// Records one spent replay attempt against a row.
    func noteAttempt(id: String, error: String) async
}
