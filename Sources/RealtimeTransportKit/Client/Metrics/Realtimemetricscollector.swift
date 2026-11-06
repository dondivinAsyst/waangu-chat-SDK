//
//  Realtimemetricscollector.swift
//  AppModules
//
//  Created by Asyst on 6/4/26.
//

// MARK: - RealtimeKit/Metrics/RealtimeMetricsCollector.swift
//
// Module  : RealtimeKit (public — utilisé par l'App Target)
// Rôle    : Implémentation de RealtimeMetricsDelegate.
//           Collecte les métriques et les route vers :
//           - OSSignpost (Instruments / Time Profiler)
//           - Callbacks custom (Firebase, Datadog, console)
//
// Design  : Singleton partagé (accessible depuis App Target et RealtimeAssembly).
//           Thread-safe via actor isolation.
//           Snapshot périodique toutes les 60 secondes.

import Foundation
import WaanguCoreKit
import os.signpost

// MARK: - RealtimeMetricsCollector

/// Collecte et route les métriques temps réel.
///
/// ```swift
/// // DependencyContainer
/// metricsDelegate: RealtimeMetricsCollector.shared
///
/// // Accès aux stats en temps réel
/// let snapshot = await RealtimeMetricsCollector.shared.currentSnapshot()
/// ```
public final class RealtimeMetricsCollector: RealtimeMetricsDelegate, @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = RealtimeMetricsCollector()

    // Thread safety via NSLock (remplace l'actor isolation)
    private let lock = NSLock()

    // MARK: - OSSignpost

    private let signposter = OSSignposter(
        subsystem: "com.waangu.realtimekit",
        category: "Realtime"
    )

    // MARK: - Counters

    private var messagesReceived: Int = 0
    private var messagesPublished: Int = 0
    private var duplicatesFiltered: Int = 0
    private var reconnectionCount: Int = 0
    private var messageLossCount: Int = 0

    // MARK: - Latency Tracking

    private var receiveLatencies: [TimeInterval] = []
    private var publishLatencies: [TimeInterval] = []
    private let maxLatencySamples = 100

    // MARK: - Custom Callback

    /// Callback optionnel vers un système de monitoring externe.
    /// Assigné par l'App Target (Firebase, Datadog, etc.).
    public var onSnapshot: (@Sendable (RealtimePerformanceSnapshot) -> Void)?

    // MARK: - Snapshot Timer

    private var snapshotTask: Task<Void, Never>?
    private let snapshotInterval: TimeInterval = 60

    // MARK: - Init

    private init() {
        startPeriodicSnapshots()
    }

    // MARK: - RealtimeMetricsDelegate

    public func didReceiveMessage(
        topic: RealtimeTopic,
        latency: TimeInterval?,
        size: Int
    ) {
        lock.lock(); messagesReceived += 1; lock.unlock()

        if let latency {
            lock.lock()
            receiveLatencies.append(latency)
            if receiveLatencies.count > maxLatencySamples { receiveLatencies.removeFirst() }
            lock.unlock()
        }

        signposter.emitEvent("message.received", "\(topic.path) (\(size)B)")
    }

    public func didPublishMessage(
        topic: RealtimeTopic,
        qos: RealtimeQoS,
        latency: TimeInterval?
    ) {
        lock.lock(); messagesPublished += 1; lock.unlock()

        if let latency {
            lock.lock()
            publishLatencies.append(latency)
            if publishLatencies.count > maxLatencySamples { publishLatencies.removeFirst() }
            lock.unlock()
        }
    }

    public func didLoseMessage(
        topic: RealtimeTopic,
        reason: MessageLossReason
    ) {
        lock.lock(); messageLossCount += 1; lock.unlock()
        signposter.emitEvent("message.lost", "\(topic.path) — \(reason)")
    }

    public func didDeduplicateMessage(
        topic: RealtimeTopic,
        messageId: MessageID
    ) {
        lock.lock(); duplicatesFiltered += 1; lock.unlock()
    }

    public func didChangeConnectionState(
        from: RealtimeConnectionState,
        to: RealtimeConnectionState
    ) {
        signposter.emitEvent(
            "connection.state",
            "\(from.debugLabel) → \(to.debugLabel)"
        )
    }

    public func didReconnect(
        attempt: Int,
        transport: String,
        duration: TimeInterval
    ) {
        lock.lock(); reconnectionCount += 1; lock.unlock()
        signposter.emitEvent(
            "reconnected",
            "attempt:\(attempt) transport:\(transport) duration:\(String(format:"%.1f",duration))s"
        )
    }

    public func didFallbackTransport(
        from: String,
        to: String,
        reason: String
    ) {
        signposter.emitEvent("transport.fallback", "\(from) → \(to): \(reason)")
    }

    public func didFlushOfflineQueue(
        messageCount: Int,
        expiredCount: Int,
        duration: TimeInterval
    ) {
        signposter.emitEvent(
            "queue.flushed",
            "sent:\(messageCount) expired:\(expiredCount)"
        )
    }

    public func didChangeSubscriptionCount(
        activeCount: Int,
        event: SubscriptionEvent
    ) {
        signposter.emitEvent("subscription.change", "\(event) → total:\(activeCount)")
    }

    public func didCollectPerformanceSnapshot(
        _ snapshot: RealtimePerformanceSnapshot
    ) {
        onSnapshot?(snapshot)
    }

    // MARK: - Public — Current Snapshot

    /// Retourne un snapshot des métriques courantes.
    public func currentSnapshot( // @unchecked Sendable — lock protects reads
        activeSubscriptions: Int = 0,
        offlineQueueSize: Int = 0
    ) -> RealtimePerformanceSnapshot {
        RealtimePerformanceSnapshot(
            messagesReceived: messagesReceived,
            messagesPublished: messagesPublished,
            averageReceiveLatencyMs: averageLatency(receiveLatencies).map { $0 * 1000 },
            averagePublishLatencyMs: averageLatency(publishLatencies).map { $0 * 1000 },
            duplicatesFiltered: duplicatesFiltered,
            reconnectionCount: reconnectionCount,
            activeSubscriptions: activeSubscriptions,
            offlineQueueSize: offlineQueueSize,
            periodSeconds: snapshotInterval
        )
    }

    /// Remet tous les compteurs à zéro.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        messagesReceived = 0
        messagesPublished = 0
        duplicatesFiltered = 0
        reconnectionCount = 0
        messageLossCount = 0
        receiveLatencies.removeAll()
        publishLatencies.removeAll()
    }

    // MARK: - Private — Helpers

    private func averageLatency(_ samples: [TimeInterval]) -> TimeInterval? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private func startPeriodicSnapshots() {
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(60 * 1_000_000_000))
                guard let self, !Task.isCancelled else { break }
                let snapshot = self.currentSnapshot()
                self.didCollectPerformanceSnapshot(snapshot)
            }
        }
    }
}
