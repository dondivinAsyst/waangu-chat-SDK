//
//  SyncHealthMonitor.swift
//  CoreKit
//
//  Monitors sync health and provides heartbeat indicators
//

import Foundation
import Combine

// MARK: - Sync Health Status

public enum SyncHealthStatus: String, Codable {
    case healthy       // All syncs working, recent activity
    case stale         // No sync in last 30 minutes
    case degraded      // Some syncs failing
    case offline       // No network or all syncs failing
}

// MARK: - Sync Topic

public enum SyncTopic: String, Codable, CaseIterable {
    case conversations = "conversations"
    case messages      = "messages"
    case stories       = "stories"
    case calls         = "calls"
    case realtime      = "realtime"
    case presence      = "presence"
}

// MARK: - Sync Metrics

public struct SyncMetrics: Codable {
    public let topic: SyncTopic
    public let lastSyncTime: Date?
    public let lastSuccessTime: Date?
    public let lastFailureTime: Date?
    public let consecutiveFailures: Int
    public let totalSyncs: Int
    public let totalFailures: Int
    
    public var status: SyncHealthStatus {
        guard let lastSuccess = lastSuccessTime else {
            return .offline
        }
        
        let timeSinceLastSync = Date().timeIntervalSince(lastSuccess)
        
        // Check consecutive failures
        if consecutiveFailures >= 3 {
            return .offline
        } else if consecutiveFailures > 0 {
            return .degraded
        }
        
        // Check staleness
        if timeSinceLastSync > 30 * 60 { // 30 minutes
            return .stale
        }
        
        return .healthy
    }
    
    public var healthEmoji: String {
        switch status {
        case .healthy:   return "💚"
        case .stale:     return "💛"
        case .degraded:  return "🧡"
        case .offline:   return "❤️"
        }
    }
    
    public init(
        topic: SyncTopic,
        lastSyncTime: Date? = nil,
        lastSuccessTime: Date? = nil,
        lastFailureTime: Date? = nil,
        consecutiveFailures: Int = 0,
        totalSyncs: Int = 0,
        totalFailures: Int = 0
    ) {
        self.topic = topic
        self.lastSyncTime = lastSyncTime
        self.lastSuccessTime = lastSuccessTime
        self.lastFailureTime = lastFailureTime
        self.consecutiveFailures = consecutiveFailures
        self.totalSyncs = totalSyncs
        self.totalFailures = totalFailures
    }
}

// MARK: - Sync Health Monitor

public final class SyncHealthMonitor: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = SyncHealthMonitor()
    
    // MARK: - Published Properties
    //
    // Read-only copies for SwiftUI. They are assigned on the main thread only,
    // from snapshots taken under `lock`. Code that needs the current value from
    // any thread uses the accessors below, which read the locked storage.
    
    @Published public private(set) var overallStatus: SyncHealthStatus = .healthy
    @Published public private(set) var metrics: [SyncTopic: SyncMetrics] = [:]
    @Published public private(set) var subscriptions: Set<String> = []
    @Published public private(set) var lastHeartbeat: Date?
    
    // MARK: - Private Properties
    
    private let userDefaults: UserDefaults
    private let metricsKey = "sync.health.metrics"
    private let subscriptionsKey = "sync.health.subscriptions"
    private var heartbeatTimer: Timer?   // touched on the main thread only
    
    /// One lock for everything below. The monitor is a singleton called from
    /// several repositories at once when chat starts: an unguarded dictionary
    /// mutated from two threads crashes in `Dictionary.subscript(_:)=`.
    private let lock = NSLock()
    private var storedMetrics: [SyncTopic: SyncMetrics] = [:]
    private var storedSubscriptions: Set<String> = []
    private var storedHeartbeat: Date?
    /// Bumped on every change. A snapshot older than the one already shown is
    /// dropped on the main thread, so two threads cannot publish out of order.
    private var version = 0
    private var publishedVersion = 0   // main thread only
    
    private struct Snapshot {
        let version: Int
        let metrics: [SyncTopic: SyncMetrics]
        let subscriptions: Set<String>
        let heartbeat: Date?
        let overallStatus: SyncHealthStatus
    }
    
    // MARK: - Initialization
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadMetrics()
        startHeartbeat()
    }
    
    deinit {
        heartbeatTimer?.invalidate()
    }
    
    // MARK: - Locking and publishing
    
    /// Synchronous on purpose: `NSLock` must not be taken directly in `async` code.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
    
    /// Call with `lock` held.
    private func makeSnapshot() -> Snapshot {
        version += 1
        return Snapshot(
            version: version,
            metrics: storedMetrics,
            subscriptions: storedSubscriptions,
            heartbeat: storedHeartbeat,
            overallStatus: Self.computeOverallStatus(storedMetrics)
        )
    }
    
    /// Call with `lock` released. `@Published` is never assigned off the main thread.
    private func publish(_ snapshot: Snapshot) {
        DispatchQueue.main.async { [weak self] in
            guard let self, snapshot.version > self.publishedVersion else { return }
            self.publishedVersion = snapshot.version
            self.metrics = snapshot.metrics
            self.subscriptions = snapshot.subscriptions
            self.lastHeartbeat = snapshot.heartbeat
            self.overallStatus = snapshot.overallStatus
        }
    }
    
    // MARK: - Heartbeat
    
    private func startHeartbeat() {
        // Scheduled on the main run loop: the first caller of `shared` may be a
        // background thread, whose run loop never runs.
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                self?.beat()
            }
        }
    }
    
    private func beat() {
        let snapshot: Snapshot = withLock {
            storedHeartbeat = Date()
            return makeSnapshot()
        }
        publish(snapshot)
    }
    
    // MARK: - Sync Recording
    
    public func recordSyncStart(topic: SyncTopic) {
        let snapshot: Snapshot = withLock {
            let metric = storedMetrics[topic] ?? SyncMetrics(topic: topic)
            
            storedMetrics[topic] = SyncMetrics(
                topic: metric.topic,
                lastSyncTime: Date(),
                lastSuccessTime: metric.lastSuccessTime,
                lastFailureTime: metric.lastFailureTime,
                consecutiveFailures: metric.consecutiveFailures,
                totalSyncs: metric.totalSyncs + 1,
                totalFailures: metric.totalFailures
            )
            saveMetrics()
            return makeSnapshot()
        }
        publish(snapshot)
        
        debugLog("[SyncHealth] \(topic.rawValue.capitalized) sync started")
    }
    
    public func recordSyncSuccess(topic: SyncTopic, itemsSynced: Int = 0) {
        var emoji = ""
        let snapshot: Snapshot = withLock {
            let metric = storedMetrics[topic] ?? SyncMetrics(topic: topic)
            
            let updatedMetric = SyncMetrics(
                topic: metric.topic,
                lastSyncTime: metric.lastSyncTime,
                lastSuccessTime: Date(),
                lastFailureTime: metric.lastFailureTime,
                consecutiveFailures: 0, // Reset on success
                totalSyncs: metric.totalSyncs,
                totalFailures: metric.totalFailures
            )
            storedMetrics[topic] = updatedMetric
            saveMetrics()
            emoji = updatedMetric.healthEmoji
            return makeSnapshot()
        }
        publish(snapshot)
        
        debugLog("[SyncHealth] \(emoji) \(topic.rawValue.capitalized) sync succeeded (\(itemsSynced) items)")
    }
    
    public func recordSyncFailure(topic: SyncTopic, error: Error) {
        var emoji = ""
        let snapshot: Snapshot = withLock {
            let metric = storedMetrics[topic] ?? SyncMetrics(topic: topic)
            
            let updatedMetric = SyncMetrics(
                topic: metric.topic,
                lastSyncTime: metric.lastSyncTime,
                lastSuccessTime: metric.lastSuccessTime,
                lastFailureTime: Date(),
                consecutiveFailures: metric.consecutiveFailures + 1,
                totalSyncs: metric.totalSyncs,
                totalFailures: metric.totalFailures + 1
            )
            storedMetrics[topic] = updatedMetric
            saveMetrics()
            emoji = updatedMetric.healthEmoji
            return makeSnapshot()
        }
        publish(snapshot)
        
        debugLog("[SyncHealth] \(emoji) \(topic.rawValue.capitalized) sync failed: \(error.localizedDescription)")
    }
    
    // MARK: - Subscriptions
    
    public func addSubscription(_ topic: String) {
        let snapshot: Snapshot = withLock {
            storedSubscriptions.insert(topic)
            saveSubscriptions()
            return makeSnapshot()
        }
        publish(snapshot)
        debugLog("[SyncHealth] 📡 Subscribed to: \(topic)")
    }
    
    public func removeSubscription(_ topic: String) {
        let snapshot: Snapshot = withLock {
            storedSubscriptions.remove(topic)
            saveSubscriptions()
            return makeSnapshot()
        }
        publish(snapshot)
        debugLog("[SyncHealth] 📡 Unsubscribed from: \(topic)")
    }
    
    public func clearSubscriptions() {
        let snapshot: Snapshot = withLock {
            storedSubscriptions.removeAll()
            saveSubscriptions()
            return makeSnapshot()
        }
        publish(snapshot)
        debugLog("[SyncHealth] 📡 All subscriptions cleared")
    }
    
    // MARK: - Status Calculation
    
    private static func computeOverallStatus(_ metrics: [SyncTopic: SyncMetrics]) -> SyncHealthStatus {
        let statuses = metrics.values.map { $0.status }
        
        if statuses.contains(.offline) {
            return .offline
        } else if statuses.contains(.degraded) {
            return .degraded
        } else if statuses.contains(.stale) {
            return .stale
        } else if !statuses.isEmpty {
            return .healthy
        } else {
            return .offline
        }
    }
    
    // MARK: - Persistence
    
    /// Runs from `init`, before the instance is shared: nothing else can touch it
    /// yet, so the `@Published` values are set directly (same thread as `init`).
    private func loadMetrics() {
        if let data = userDefaults.data(forKey: metricsKey),
           let decoded = try? JSONDecoder().decode([SyncTopic: SyncMetrics].self, from: data) {
            storedMetrics = decoded
        }
        
        if let data = userDefaults.data(forKey: subscriptionsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            storedSubscriptions = decoded
        }
        
        let snapshot = makeSnapshot()
        publishedVersion = snapshot.version
        metrics = snapshot.metrics
        subscriptions = snapshot.subscriptions
        lastHeartbeat = snapshot.heartbeat
        overallStatus = snapshot.overallStatus
    }
    
    /// Call with `lock` held.
    private func saveMetrics() {
        if let encoded = try? JSONEncoder().encode(storedMetrics) {
            userDefaults.set(encoded, forKey: metricsKey)
        }
    }
    
    /// Call with `lock` held.
    private func saveSubscriptions() {
        if let encoded = try? JSONEncoder().encode(storedSubscriptions) {
            userDefaults.set(encoded, forKey: subscriptionsKey)
        }
    }
    
    // MARK: - Public Accessors
    //
    // Read the locked storage, not the `@Published` copies, so they are correct
    // from any thread and never one main-thread hop behind.
    
    public func getMetrics(for topic: SyncTopic) -> SyncMetrics? {
        return withLock { storedMetrics[topic] }
    }
    
    public func getLastSyncTime(for topic: SyncTopic) -> Date? {
        return withLock { storedMetrics[topic]?.lastSyncTime }
    }
    
    public func getLastSuccessTime(for topic: SyncTopic) -> Date? {
        return withLock { storedMetrics[topic]?.lastSuccessTime }
    }
    
    public func getStatus(for topic: SyncTopic) -> SyncHealthStatus {
        return withLock { storedMetrics[topic]?.status ?? .offline }
    }
    
    public func getHealthSummary() -> String {
        let (current, subs, heartbeat) = withLock { (storedMetrics, storedSubscriptions, storedHeartbeat) }
        var summary = "Sync Health Summary:\n"
        
        for topic in SyncTopic.allCases {
            if let metric = current[topic] {
                let timeAgo = metric.lastSuccessTime.map { formatTimeAgo($0) } ?? "Never"
                summary += "\(metric.healthEmoji) \(topic.rawValue.capitalized): \(timeAgo)\n"
            }
        }
        
        summary += "\n📡 Subscriptions: \(subs.count) active"
        summary += "\n💓 Last heartbeat: \(heartbeat.map { formatTimeAgo($0) } ?? "Never")"
        
        return summary
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    // MARK: - Reset
    
    public func reset() {
        let snapshot: Snapshot = withLock {
            storedMetrics.removeAll()
            storedSubscriptions.removeAll()
            storedHeartbeat = nil
            userDefaults.removeObject(forKey: metricsKey)
            userDefaults.removeObject(forKey: subscriptionsKey)
            return makeSnapshot()
        }
        publish(snapshot)
        
        debugLog("[SyncHealth] 🔄 Health monitor reset")
    }
    
    // MARK: - Async Accessors for UI
    
    public func getAllMetrics() async -> [SyncHealthMetric] {
        let current = withLock { storedMetrics }
        return current.values.map { metric in
            SyncHealthMetric(
                id: metric.topic.rawValue,
                topic: metric.topic.rawValue,
                status: metric.status,
                lastSyncTime: metric.lastSyncTime,
                lastSuccessTime: metric.lastSuccessTime,
                consecutiveFailures: metric.consecutiveFailures
            )
        }
    }
    
    public func getActiveSubscriptions() async -> Set<String> {
        return withLock { storedSubscriptions }
    }
}

// MARK: - UI-Compatible Metric Model

public struct SyncHealthMetric: Identifiable {
    public let id: String
    public let topic: String
    public let status: SyncHealthStatus
    public let lastSyncTime: Date?
    public let lastSuccessTime: Date?
    public let consecutiveFailures: Int
}
