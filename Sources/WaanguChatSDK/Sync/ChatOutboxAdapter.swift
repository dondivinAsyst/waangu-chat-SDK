//
//  ChatOutboxAdapter.swift
//  WaanguChatSDK
//
//  Moved from the Waangu app target into WaanguChatSDK (SDK plan, step 1.9).
//

import Foundation
import WaanguCoreKit
import WaanguFeatureChat
import WaanguStorageKit

/// Bridges `DatabaseOutbox<ChatOutboxItem>` to `ChatOutboxEnqueuing` for FeatureChat injection.
public final class ChatOutboxAdapter: ChatOutboxEnqueuing, @unchecked Sendable {
    private let outbox: DatabaseOutbox<ChatOutboxItem>

    public init(outbox: DatabaseOutbox<ChatOutboxItem>) {
        self.outbox = outbox
    }

    public func enqueue(_ item: ChatOutboxItem) async throws {
        #if DEBUG
        // Every call site wraps this in `try?`, so a failing enqueue is otherwise
        // invisible — the action just never appears in the outbox. Logging here
        // covers all of them at once. `pendingCount` right after the write tells
        // us whether the row actually landed (on the JSON proxy fallback the
        // status filter is ignored, so it reads as "rows stored for this type").
        do {
            try await outbox.enqueue(item)
            let stored = await outbox.pendingCount
            print("[Outbox] enqueued \(item.actionTypeString) key=\(item.idempotencyKey) → stored=\(stored)")
        } catch {
            print("[Outbox] ENQUEUE FAILED \(item.actionTypeString) key=\(item.idempotencyKey) — \(error)")
            throw error
        }
        #else
        try await outbox.enqueue(item)
        #endif
    }
}

// MARK: - Settling & replay

extension ChatOutboxAdapter: ChatOutboxMaintaining {

    @discardableResult
    public func settle(
        _ actionType: ChatOutboxItemActionType,
        reference: String,
        as settlement: ChatOutboxSettlement
    ) async -> Int {
        // Same shape the factory methods build their keys from.
        let key = "\(actionType.rawValue):\(reference)"
        switch settlement {
        case .acknowledged:
            return await outbox.settle(key: key, success: true)
        case .rejected(let reason):
            return await outbox.settle(key: key, success: false, error: reason)
        }
    }

    public func pending(olderThan age: TimeInterval) async -> [ChatOutboxItem] {
        await outbox.pending(olderThan: age)
    }

    public func noteAttempt(id: String, error: String) async {
        await outbox.noteAttempt(id: id, error: error)
    }
}
