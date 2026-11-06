 //
//  DatabaseMetricsCollector.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Metrics/DatabaseMetricsCollector.swift   │
// │                                                              │
// │  PUBLIC — le App Target le configure et le passe à          │
// │  DatabaseAssembly.Config(metricsDelegate:).                  │
// │                                                              │
// │  Implémente DatabaseMetricsDelegate (CoreKit).               │
// │  Agrège les stats en mémoire et expose des callbacks         │
// │  pour brancher Firebase, Datadog, Sentry…                   │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import OSLog
import WaanguCoreKit

private let log = OSLog(subsystem: "com.superapp.storagekit", category: "db.metrics")

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseMetricsCollector
// ─────────────────────────────────────────────────────────────

public final class DatabaseMetricsCollector: DatabaseMetricsDelegate, @unchecked Sendable {

    public static let shared = DatabaseMetricsCollector()

    private let lock = NSLock()
    private var _stats: [String: NamespaceStats] = [:]
    private var statsResetDate = Date()

    // Callbacks configurés depuis le App Target
    private var onSlowQueryHandler: ((QueryMetrics) -> Void)?
    private var onErrorHandler: ((DatabaseError, DatabaseOperation, String) -> Void)?

    private init() {}

    // ─────────────────────────────────────────────────────────
    // MARK: Configuration (builder pattern)
    // ─────────────────────────────────────────────────────────

    @discardableResult
    public func onSlowQuery(_ handler: @escaping (QueryMetrics) -> Void) -> Self {
        onSlowQueryHandler = handler
        return self
    }

    @discardableResult
    public func onError(
        _ handler: @escaping (DatabaseError, DatabaseOperation, String) -> Void
    ) -> Self {
        onErrorHandler = handler
        return self
    }

    // ─────────────────────────────────────────────────────────
    // MARK: DatabaseMetricsDelegate
    // ─────────────────────────────────────────────────────────

    public func database(didExecute metrics: QueryMetrics) {
        if metrics.isSlowQuery {
            os_log(.error, log: log,
                   "SLOW [%{public}s] %{public}s — %d ms %d rows",
                   metrics.namespace, metrics.operation.rawValue,
                   metrics.duration.milliseconds, metrics.rowCount)
            onSlowQueryHandler?(metrics)
        } else {
            os_log(.debug, log: log,
                   "[%{public}s] %{public}s — %d ms",
                   metrics.namespace, metrics.operation.rawValue,
                   metrics.duration.milliseconds)
        }

        lock.withLock {
            resetIfNeeded()
            var s = _stats[metrics.namespace] ?? NamespaceStats(namespace: metrics.namespace)
            s.record(metrics)
            _stats[metrics.namespace] = s
        }
    }

    public func database(
        didFailWith error: DatabaseError,
        operation: DatabaseOperation,
        namespace: String
    ) {
        os_log(.fault, log: log,
               "ERROR [%{public}s] %{public}s — %{public}s",
               namespace, operation.rawValue,
               error.localizedDescription ?? "\(error)")
        onErrorHandler?(error, operation, namespace)

        lock.withLock {
            var s = _stats[namespace] ?? NamespaceStats(namespace: namespace)
            s.errorCount += 1
            _stats[namespace] = s
        }
    }

    public func database(
        didMigrate namespace: String,
        fromVersion: Int,
        toVersion: Int,
        duration: Duration
    ) {
        os_log(.info, log: log,
               "MIGRATION [%{public}s] v%d→v%d — %d ms",
               namespace, fromVersion, toVersion, duration.milliseconds)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Accès aux stats
    // ─────────────────────────────────────────────────────────

    public func stats(for namespace: String) -> NamespaceStats? {
        lock.withLock { _stats[namespace] }
    }

    public func allStats() -> [NamespaceStats] {
        lock.withLock { Array(_stats.values) }
    }

    public func reset() {
        lock.withLock {
            _stats = [:]
            statsResetDate = Date()
        }
    }

    private func resetIfNeeded() {
        if Date().timeIntervalSince(statsResetDate) > 3600 {
            _stats = [:]
            statsResetDate = Date()
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: NamespaceStats
// ─────────────────────────────────────────────────────────────

public struct NamespaceStats: Sendable {
    public let namespace: String
    public var totalQueries: Int = 0
    public var slowQueries: Int = 0
    public var errorCount: Int = 0
    public var totalDuration: Duration = .zero
    public var maxDuration: Duration = .zero
    public var operationCounts: [DatabaseOperation: Int] = [:]

    public var averageDuration: Duration {
        guard totalQueries > 0 else { return .zero }
        let atto = totalDuration.components.seconds * 1_000_000_000_000_000_000
                 + totalDuration.components.attoseconds
        return Duration(secondsComponent: 0, attosecondsComponent: atto / Int64(totalQueries))
    }

    public var slowQueryRate: Double {
        guard totalQueries > 0 else { return 0 }
        return Double(slowQueries) / Double(totalQueries)
    }

    init(namespace: String) { self.namespace = namespace }

    mutating func record(_ m: QueryMetrics) {
        totalQueries += 1
        if m.isSlowQuery { slowQueries += 1 }
        totalDuration += m.duration
        if m.duration > maxDuration { maxDuration = m.duration }
        operationCounts[m.operation, default: 0] += 1
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: CompositeMetricsDelegate
// ─────────────────────────────────────────────────────────────

/// Branche plusieurs delegates en parallèle.
/// Usage : Firebase + Datadog + votre propre logger simultanément.
public final class CompositeMetricsDelegate: DatabaseMetricsDelegate, @unchecked Sendable {

    private let delegates: [any DatabaseMetricsDelegate]

    public init(_ delegates: [any DatabaseMetricsDelegate]) {
        self.delegates = delegates
    }

    public func database(didExecute metrics: QueryMetrics) {
        delegates.forEach { $0.database(didExecute: metrics) }
    }

    public func database(
        didFailWith error: DatabaseError,
        operation: DatabaseOperation,
        namespace: String
    ) {
        delegates.forEach {
            $0.database(didFailWith: error, operation: operation, namespace: namespace)
        }
    }

    public func database(
        didMigrate namespace: String,
        fromVersion: Int,
        toVersion: Int,
        duration: Duration
    ) {
        delegates.forEach {
            $0.database(didMigrate: namespace, fromVersion: fromVersion,
                        toVersion: toVersion, duration: duration)
        }
    }
}
