//
//  ChatReconnectSequence.swift
//  FeatureChat
//
//  Bloc 8 §20 — what the client owes the server, in order, when the realtime
//  connection comes back (B64).
//

import Foundation

/// Runs the reconnect work as **one ordered routine**.
///
/// Before this, three observers of the connection state each started their own
/// piece — the chat outbox sweep, the finance reconciliation, the finance outbox
/// flush — with no order between them and nothing before them: a session that
/// had expired, or a conversation list that fell behind during the gap, was never
/// looked at on reconnect.
///
/// Order (Waangu 360 Bloc 8 §20):
///
/// 1. re-authentication check — a session that needs re-authenticating **stops**
///    the routine: replaying actions on a stale session helps nobody;
/// 2. membership / policy / capability / FCO refresh — no contract exists yet
///    (B35, B13, B12), so each is reported `skipped`, never invented;
/// 3. delta sync of conversations and messages;
/// 4. financial reconciliation of ambiguous objects;
/// 5. finance outbox, then chat outbox.
///
/// A failing or slow step never blocks the ones after it, except step 1.
actor ChatReconnectSequence {

    enum Trigger: Sendable {
        /// First connected state seen after launch. The chat start already runs
        /// its own sync and the finance start its own reconciliation, so only the
        /// outbox is drained — the behaviour the chat sweep loop always had.
        case startup
        /// A real transition from not connected to connected.
        case reconnect
    }

    /// What a connection-state change means for the routine.
    ///
    /// Only a transition into connected can trigger anything; staying connected
    /// never does. The **first** connection after launch is a startup whether or
    /// not the app saw a disconnected state before it: the chat start already
    /// syncs, and running a second sync next to it is exactly what produced two
    /// overlapping transactions on 2026-10-14. Every later transition into
    /// connected is a reconnection.
    static func trigger(wasConnected: Bool, hasConnectedBefore: Bool, isConnected: Bool) -> Trigger? {
        guard isConnected, !wasConnected else { return nil }
        return hasConnectedBefore ? .reconnect : .startup
    }

    enum Step: String, Sendable, CaseIterable {
        case reauthenticate
        case refreshMembership
        case refreshPolicy
        case refreshCapability
        case deltaSync
        case refreshFCO
        case refreshFinancialState
        case drainFinanceOutbox
        case drainChatOutbox
    }

    enum Outcome: Equatable, Sendable {
        case completed
        case skipped(String)
        case failed(String)
        case timedOut
    }

    enum Result: Equatable, Sendable {
        case finished
        case stoppedForReauthentication
    }

    struct Report: Equatable, Sendable {
        let result: Result
        let outcomes: [Entry]

        struct Entry: Equatable, Sendable {
            let step: Step
            let outcome: Outcome
        }

        func outcome(of step: Step) -> Outcome? {
            outcomes.first { $0.step == step }?.outcome
        }

        /// The steps that actually ran, in the order they ran.
        var ranInOrder: [Step] {
            outcomes.compactMap { entry in
                switch entry.outcome {
                case .skipped: return nil
                default: return entry.step
                }
            }
        }
    }

    struct Steps: Sendable {
        var needsReauthentication: @Sendable () async throws -> Bool
        var deltaSync: @Sendable () async throws -> Void
        var reconcileFinance: @Sendable () async -> Void
        var drainFinanceOutbox: @Sendable () async -> Void
        var drainChatOutbox: @Sendable () async -> Void
    }

    private let steps: Steps
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void

    /// Minimum gap between two delta syncs. Same value as the finance
    /// reconciliation (`FinancialReconciliationScheduler.minimumInterval`): a
    /// connection that flaps must not turn into a sync storm.
    private let minimumDeltaSyncInterval: TimeInterval

    /// A sync that does not answer must not hold the outbox back. Chosen here,
    /// not specified by any contract: to be validated with the API's real latency.
    private let deltaSyncTimeout: TimeInterval

    private var lastDeltaSync: Date?
    private var isRunning = false

    init(
        steps: Steps,
        minimumDeltaSyncInterval: TimeInterval = 30,
        deltaSyncTimeout: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() },
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.steps = steps
        self.minimumDeltaSyncInterval = minimumDeltaSyncInterval
        self.deltaSyncTimeout = deltaSyncTimeout
        self.now = now
        self.log = log
    }

    /// Runs the routine once. A second call while one is running is ignored:
    /// two overlapping passes would replay the same outbox rows twice.
    @discardableResult
    func run(_ trigger: Trigger) async -> Report? {
        guard !isRunning else {
            log("[Reconnect] already running — trigger ignored")
            return nil
        }
        isRunning = true
        defer { isRunning = false }

        var outcomes: [Report.Entry] = []
        func record(_ step: Step, _ outcome: Outcome) {
            outcomes.append(.init(step: step, outcome: outcome))
            log("[Reconnect] \(step.rawValue): \(outcome)")
        }

        if trigger == .startup {
            for step in Step.allCases where step != .drainChatOutbox {
                record(step, .skipped("startup: the chat start already does this"))
            }
            await steps.drainChatOutbox()
            record(.drainChatOutbox, .completed)
            return Report(result: .finished, outcomes: outcomes)
        }

        // 1. Re-authentication.
        do {
            if try await steps.needsReauthentication() {
                record(.reauthenticate, .failed("re-authentication required"))
                for step in Step.allCases.dropFirst() {
                    record(step, .skipped("stopped: re-authentication required"))
                }
                return Report(result: .stoppedForReauthentication, outcomes: outcomes)
            }
            record(.reauthenticate, .completed)
        } catch {
            // Unable to read the session: not a reason to hold the outbox back.
            record(.reauthenticate, .failed("\(error)"))
        }

        // 2. Refreshes that have no contract yet.
        record(.refreshMembership, .skipped("no membership contract (B35)"))
        record(.refreshPolicy, .skipped("no policy contract (B13)"))
        record(.refreshCapability, .skipped("no capability contract (B35)"))

        // 3. Delta sync.
        if let last = lastDeltaSync, now().timeIntervalSince(last) < minimumDeltaSyncInterval {
            record(.deltaSync, .skipped("ran \(Int(now().timeIntervalSince(last))) s ago"))
        } else {
            lastDeltaSync = now()
            record(.deltaSync, await runWithTimeout(deltaSyncTimeout, steps.deltaSync))
        }

        // 4. Financial state. FCO refresh has no separate contract (B12): ambiguous
        //    objects are refreshed together with the financial state.
        record(.refreshFCO, .skipped("no FCO contract (B12); ambiguous objects refresh with the financial state"))
        await steps.reconcileFinance()
        record(.refreshFinancialState, .completed)

        // 5. Outboxes.
        await steps.drainFinanceOutbox()
        record(.drainFinanceOutbox, .completed)
        await steps.drainChatOutbox()
        record(.drainChatOutbox, .completed)

        return Report(result: .finished, outcomes: outcomes)
    }

    private func runWithTimeout(
        _ seconds: TimeInterval,
        _ work: @escaping @Sendable () async throws -> Void
    ) async -> Outcome {
        await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                do {
                    try await work()
                    return .completed
                } catch {
                    return .failed("\(error)")
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }
}

// MARK: - Metrics (plan SDK, step 1.13)

extension ChatReconnectSequence.Report {

    /// One `reconnect` metric, plus one `sync_failure` per step that failed or timed out.
    ///
    /// Only the step name and the outcome kind are reported: a failure's own text can quote
    /// data, and a metric carries none.
    func metrics(trigger: ChatReconnectSequence.Trigger, durationMs: Int) -> [ChatMetric] {
        let triggerName: String
        switch trigger {
        case .startup:   triggerName = "startup"
        case .reconnect: triggerName = "reconnect"
        }
        let resultName: String
        switch result {
        case .finished:                    resultName = "finished"
        case .stoppedForReauthentication:  resultName = "stopped_for_reauthentication"
        }

        let failedSteps = outcomes.filter {
            switch $0.outcome {
            case .failed, .timedOut: return true
            case .completed, .skipped: return false
            }
        }

        var metrics = [ChatMetric(name: ChatMetricName.reconnect,
                                  durationMs: durationMs,
                                  attributes: ["trigger": triggerName,
                                               "result": resultName,
                                               "failed_steps": String(failedSteps.count)])]
        for entry in failedSteps {
            let kind: String
            if case .timedOut = entry.outcome { kind = "timed_out" } else { kind = "failed" }
            metrics.append(ChatMetric(name: ChatMetricName.syncFailure,
                                      attributes: ["source": "reconnect",
                                                   "step": entry.step.rawValue,
                                                   "outcome": kind]))
        }
        return metrics
    }
}
