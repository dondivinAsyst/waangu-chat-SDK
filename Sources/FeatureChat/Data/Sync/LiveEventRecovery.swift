//
//  LiveEventRecovery.swift
//  FeatureChat
//
//  N-02, SDK plan step 1.14 — what a refused live event triggers.
//

import Foundation

/// Runs one delta sync after a live event could not be written. Further refusals while
/// it is pending add nothing: that sync re-reads them all. If the write keeps failing the
/// event stays unstored, which the log shows; it is never reported applied.
///
/// An actor, so two refusals arriving together cannot both see "nothing pending" and
/// start two syncs — the plain `Task?` property on `ChatFeature` it replaces could.
actor LiveEventRecovery {

    private let delayNanoseconds: UInt64
    private let deltaSync: @Sendable () async -> Void
    private var pending: Task<Void, Never>?

    /// - Parameters:
    ///   - delayNanoseconds: wait before syncing, so a burst of refusals is read once.
    ///   - deltaSync: the same sync a reconnect runs.
    init(delayNanoseconds: UInt64 = 5_000_000_000, deltaSync: @escaping @Sendable () async -> Void) {
        self.delayNanoseconds = delayNanoseconds
        self.deltaSync = deltaSync
    }

    /// `true` when this call scheduled the sync, `false` when one was already pending.
    @discardableResult
    func schedule() -> Bool {
        guard pending == nil else { return false }
        pending = Task {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            if !Task.isCancelled {
                await deltaSync()
            }
            self.pending = nil
        }
        return true
    }

    /// Waits for the pending sync, if any. Used by tests.
    func waitUntilIdle() async {
        await pending?.value
    }
}
