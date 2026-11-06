// MARK: - StorageKit/Sync/DatabaseOutbox.swift
//
// Module  : StorageKit
// Rôle    : Implémentation de OutboxFlushing — stockage SQLite + flush HTTP batch.
//           Dedup à l'enqueue via idempotencyKey.

import Foundation
import WaanguCoreKit

// MARK: - DatabaseOutbox

public actor DatabaseOutbox<Item: OutboxItemProtocol & Storable>: OutboxFlushing
where Item.ID == String {

    private let database: any DatabaseRepositoryProtocol
    private let config: OutboxConfiguration
    private let performFlush: @Sendable ([Item]) async throws -> [OutboxFlushResult]
    private var isFlushing: Bool = false

    public init(
        database: any DatabaseRepositoryProtocol,
        config: OutboxConfiguration = .default,
        flush: @escaping @Sendable ([Item]) async throws -> [OutboxFlushResult]
    ) {
        self.database = database
        self.config = config
        self.performFlush = flush
    }

    // MARK: - Enqueue (avec dedup)

    public func enqueue(_ item: Item) async throws {
        // Dedup — refuser si un item pending a la même idempotencyKey.
        // Colonnes en snake_case : le schema builder normalise `indexedFields`,
        // et FilterSpec est passé au SQL tel quel.
        let existing = try await database.fetch(
            Item.self,
            query: QuerySpec(
                filter: FilterSpec(
                    "idempotency_key = %@ AND sync_status IN (%@, %@)",
                    .string(item.idempotencyKey),
                    .string(OutboxSyncStatus.pending.rawValue),
                    .string(OutboxSyncStatus.syncing.rawValue)
                ),
                limit: 1
            )
        )

        guard existing.isEmpty else {
            #if DEBUG
            print("[Outbox:\(Item.self)] Dedup: \(item.idempotencyKey) already pending")
            #endif
            return
        }

        var mutableItem = item
        mutableItem.syncStatus = .pending
        mutableItem.retryCount = 0
        try await database.save(mutableItem)
    }

    // MARK: - Flush

    @discardableResult
    public func flush() async -> [OutboxFlushResult] {
        guard !isFlushing else { return [] }
        isFlushing = true
        defer { isFlushing = false }

        await recoverStuckItems()

        var collectedResults: [OutboxFlushResult] = []
        // Un item déjà tenté dans ce passage attend le suivant (reconnexion, retour au premier
        // plan) : le reprendre tout de suite épuisait ses essais en quelques secondes, et une
        // coupure brève le marquait `.failed` pour de bon.
        var attemptedThisFlush = Set<String>()

        while !Task.isCancelled {
            let batch = await fetchPending(limit: config.batchSize, excluding: attemptedThisFlush)
            guard !batch.isEmpty else { break }
            attemptedThisFlush.formUnion(batch.map(\.id))

            await markSyncing(batch)

            do {
                let results = try await performFlush(batch)
                collectedResults.append(contentsOf: results)

                for result in results {
                    if result.success {
                        await markSynced(id: result.localId)
                    } else if result.isRetryable {
                        await incrementRetry(id: result.localId, error: result.error ?? "Unknown")
                    } else {
                        await markFailed(id: result.localId, error: result.error ?? "Permanent")
                    }
                }
            } catch {
                for item in batch {
                    await incrementRetry(id: item.id, error: error.localizedDescription)
                }
                break
            }

            if config.interBatchDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(config.interBatchDelay * 1_000_000_000))
            }
        }

        await cleanupSynced()
        return collectedResults
    }

    // MARK: - Settle (acknowledgement-driven)

    /// Settles every unsettled row whose idempotency key is `key`, or starts with
    /// `key` followed by a separator — some keys carry a trailing discriminator
    /// (the delete key ends in `:true`/`:false`), which an exact match would miss.
    ///
    /// - Returns: how many rows changed. Zero means the acknowledgement belongs to
    ///   an action this device never queued — worth logging, not an error.
    @discardableResult
    public func settle(key: String, success: Bool, error: String? = nil) async -> Int {
        var candidates = await fetch(status: .pending)
        candidates += await fetch(status: .syncing)

        let matches = candidates.filter {
            $0.idempotencyKey == key || $0.idempotencyKey.hasPrefix(key + ":")
        }

        for var item in matches {
            item.syncStatus = success ? .synced : .failed
            item.lastError = error
            try? await database.save(item)
        }

        return matches.count
    }

    // MARK: - Sweep (reconnect)

    /// Rows still waiting for an acknowledgement past `age`, oldest first — the
    /// order they were queued in, which is the order they must be replayed in.
    public func pending(olderThan age: TimeInterval) async -> [Item] {
        let cutoff = Date().addingTimeInterval(-age)
        return await fetch(status: .pending)
            .filter { $0.createdAt < cutoff }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Records one spent attempt. Past `maxRetries` the row is marked failed and
    /// stops being swept, so an action the server never acknowledges cannot be
    /// replayed forever.
    public func noteAttempt(id: String, error: String) async {
        await incrementRetry(id: id, error: error)
    }

    // MARK: - Pending Count

    public var pendingCount: Int {
        get async {
            (try? await database.count(
                Item.self,
                query: QuerySpec(
                    filter: FilterSpec("sync_status = %@", .string(OutboxSyncStatus.pending.rawValue))
                )
            )) ?? 0
        }
    }

    // MARK: - Private — Queries

    // Only `indexedFields` become real columns on a dedicated table, under their
    // snake_case names; everything else — `createdAt` included — stays inside the
    // JSON payload. Sorting or filtering on such a field in SQL raises "no such
    // column", the throw is swallowed, and the outbox silently reports itself
    // empty. So the queries below touch `sync_status` alone, and the ordering and
    // age comparisons happen in Swift, over a set that is small by construction.

    private func fetchPending(limit: Int, excluding attempted: Set<String> = []) async -> [Item] {
        let pending = await fetch(status: .pending)
        return pending
            .filter { !attempted.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    private func fetch(status: OutboxSyncStatus) async -> [Item] {
        (try? await database.fetch(
            Item.self,
            query: QuerySpec(
                filter: FilterSpec("sync_status = %@", .string(status.rawValue))
            )
        )) ?? []
    }

    // MARK: - Private — Status Transitions

    private func markSyncing(_ items: [Item]) async {
        for var item in items {
            item.syncStatus = .syncing
            try? await database.save(item)
        }
    }

    private func markSynced(id: String) async {
        guard var item = try? await database.fetchOne(Item.self, id: id) else { return }
        item.syncStatus = .synced
        try? await database.save(item)
    }

    private func incrementRetry(id: String, error: String) async {
        guard var item = try? await database.fetchOne(Item.self, id: id) else { return }
        item.retryCount += 1
        item.lastError = error
        item.syncStatus = item.retryCount >= config.maxRetries ? .failed : .pending
        try? await database.save(item)
    }

    private func markFailed(id: String, error: String) async {
        guard var item = try? await database.fetchOne(Item.self, id: id) else { return }
        item.syncStatus = .failed
        item.lastError = error
        try? await database.save(item)
    }

    // MARK: - Private — Crash Recovery

    private func recoverStuckItems() async {
        let cutoff = Date().addingTimeInterval(-config.stuckTimeout)
        let stuck = await fetch(status: .syncing)
            .filter { $0.createdAt < cutoff }

        for var item in stuck {
            item.syncStatus = .pending
            try? await database.save(item)
        }

        #if DEBUG
        if !stuck.isEmpty {
            print("[Outbox:\(Item.self)] Recovered \(stuck.count) stuck items")
        }
        #endif
    }

    // MARK: - Private — Cleanup

    private func cleanupSynced() async {
        let cutoff = Date().addingTimeInterval(-config.syncedRetention)
        let old = await fetch(status: .synced)
            .filter { $0.createdAt < cutoff }

        for item in old {
            try? await database.delete(Item.self, id: item.id)
        }
    }
}
