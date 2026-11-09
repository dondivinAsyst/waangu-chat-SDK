//
//  SyncHealthMonitorConcurrencyTests.swift
//  CoreKitTests
//
//  `SyncHealthMonitor` is a singleton called from several repositories at once
//  when chat starts. It crashed in `metrics[topic] = …` under that load.
//

import XCTest
@testable import WaanguCoreKit

final class SyncHealthMonitorConcurrencyTests: XCTestCase {

    private struct Boom: Error {}

    private func makeMonitor() -> (SyncHealthMonitor, UserDefaults, String) {
        let suite = "SyncHealthMonitorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (SyncHealthMonitor(userDefaults: defaults), defaults, suite)
    }

    func test_concurrentRecordingAndSubscriptions_doNotCrash_andCountEveryStart() {
        let (monitor, defaults, suite) = makeMonitor()
        defer { defaults.removePersistentDomain(forName: suite) }

        let iterations = 1_000
        let topics = SyncTopic.allCases

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let topic = topics[i % topics.count]
            monitor.recordSyncStart(topic: topic)
            switch i % 3 {
            case 0: monitor.recordSyncSuccess(topic: topic, itemsSynced: i)
            case 1: monitor.recordSyncFailure(topic: topic, error: Boom())
            default: break
            }
            monitor.addSubscription("topic-\(i % 25)")
            if i % 7 == 0 { monitor.removeSubscription("topic-\((i + 1) % 25)") }
            _ = monitor.getMetrics(for: topic)
            _ = monitor.getHealthSummary()
        }

        let total = topics.reduce(0) { $0 + (monitor.getMetrics(for: $1)?.totalSyncs ?? 0) }
        XCTAssertEqual(total, iterations)

        // What was persisted decodes and agrees with the in-memory state.
        let data = defaults.data(forKey: "sync.health.metrics")
        let saved = data.flatMap { try? JSONDecoder().decode([SyncTopic: SyncMetrics].self, from: $0) }
        XCTAssertEqual(saved?.values.reduce(0) { $0 + $1.totalSyncs }, iterations)
    }

    func test_publishedCopiesCatchUpOnTheMainThread() {
        let (monitor, defaults, suite) = makeMonitor()
        defer { defaults.removePersistentDomain(forName: suite) }

        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            monitor.recordSyncStart(topic: .messages)
        }

        let settled = expectation(description: "main-thread snapshot applied")
        DispatchQueue.main.async { DispatchQueue.main.async { settled.fulfill() } }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(monitor.metrics[.messages]?.totalSyncs, 200)
    }

    func test_storedFormatAndKeysAreUnchanged() {
        let (monitor, defaults, suite) = makeMonitor()
        defer { defaults.removePersistentDomain(forName: suite) }

        monitor.recordSyncStart(topic: .calls)
        monitor.addSubscription("a")

        XCTAssertNotNil(defaults.data(forKey: "sync.health.metrics"))
        let subs = defaults.data(forKey: "sync.health.subscriptions")
            .flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) }
        XCTAssertEqual(subs, ["a"])

        // A fresh instance over the same defaults decodes what the first one saved.
        let reloaded = SyncHealthMonitor(userDefaults: defaults)
        XCTAssertEqual(reloaded.getMetrics(for: .calls)?.totalSyncs, 1)
    }
}
