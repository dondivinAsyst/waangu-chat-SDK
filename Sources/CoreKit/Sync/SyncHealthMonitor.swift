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
    
    @Published public private(set) var overallStatus: SyncHealthStatus = .healthy
    @Published public private(set) var metrics: [SyncTopic: SyncMetrics] = [:]
    @Published public private(set) var subscriptions: Set<String> = []
    @Published public private(set) var lastHeartbeat: Date?
    
    // MARK: - Private Properties
    
    private let userDefaults: UserDefaults
    private let metricsKey = "sync.health.metrics"
    private let subscriptionsKey = "sync.health.subscriptions"
    private var heartbeatTimer: Timer?
    
    // MARK: - Initialization
    
    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadMetrics()
        startHeartbeat()
    }
    
    deinit {
        heartbeatTimer?.invalidate()
    }
    
    // MARK: - Heartbeat
    
    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.beat()
        }
    }
    
    private func beat() {
        lastHeartbeat = Date()
        updateOverallStatus()
    }
    
    // MARK: - Sync Recording
    
    public func recordSyncStart(topic: SyncTopic) {
        var metric = metrics[topic] ?? SyncMetrics(topic: topic)
        
        // Create new metrics with updated values
        let updatedMetric = SyncMetrics(
            topic: metric.topic,
            lastSyncTime: Date(),
            lastSuccessTime: metric.lastSuccessTime,
            lastFailureTime: metric.lastFailureTime,
            consecutiveFailures: metric.consecutiveFailures,
            totalSyncs: metric.totalSyncs + 1,
            totalFailures: metric.totalFailures
        )
        
        metrics[topic] = updatedMetric
        saveMetrics()
        
        debugLog("[SyncHealth] \(topic.rawValue.capitalized) sync started")
    }
    
    public func recordSyncSuccess(topic: SyncTopic, itemsSynced: Int = 0) {
        var metric = metrics[topic] ?? SyncMetrics(topic: topic)
        
        let updatedMetric = SyncMetrics(
            topic: metric.topic,
            lastSyncTime: metric.lastSyncTime,
            lastSuccessTime: Date(),
            lastFailureTime: metric.lastFailureTime,
            consecutiveFailures: 0, // Reset on success
            totalSyncs: metric.totalSyncs,
            totalFailures: metric.totalFailures
        )
        
        metrics[topic] = updatedMetric
        saveMetrics()
        updateOverallStatus()
        
        debugLog("[SyncHealth] \(updatedMetric.healthEmoji) \(topic.rawValue.capitalized) sync succeeded (\(itemsSynced) items)")
    }
    
    public func recordSyncFailure(topic: SyncTopic, error: Error) {
        var metric = metrics[topic] ?? SyncMetrics(topic: topic)
        
        let updatedMetric = SyncMetrics(
            topic: metric.topic,
            lastSyncTime: metric.lastSyncTime,
            lastSuccessTime: metric.lastSuccessTime,
            lastFailureTime: Date(),
            consecutiveFailures: metric.consecutiveFailures + 1,
            totalSyncs: metric.totalSyncs,
            totalFailures: metric.totalFailures + 1
        )
        
        metrics[topic] = updatedMetric
        saveMetrics()
        updateOverallStatus()
        
        debugLog("[SyncHealth] \(updatedMetric.healthEmoji) \(topic.rawValue.capitalized) sync failed: \(error.localizedDescription)")
    }
    
    // MARK: - Subscriptions
    
    public func addSubscription(_ topic: String) {
        subscriptions.insert(topic)
        saveSubscriptions()
        debugLog("[SyncHealth] 📡 Subscribed to: \(topic)")
    }
    
    public func removeSubscription(_ topic: String) {
        subscriptions.remove(topic)
        saveSubscriptions()
        debugLog("[SyncHealth] 📡 Unsubscribed from: \(topic)")
    }
    
    public func clearSubscriptions() {
        subscriptions.removeAll()
        saveSubscriptions()
        debugLog("[SyncHealth] 📡 All subscriptions cleared")
    }
    
    // MARK: - Status Calculation
    
    private func updateOverallStatus() {
        let statuses = metrics.values.map { $0.status }
        
        if statuses.contains(.offline) {
            overallStatus = .offline
        } else if statuses.contains(.degraded) {
            overallStatus = .degraded
        } else if statuses.contains(.stale) {
            overallStatus = .stale
        } else if !statuses.isEmpty {
            overallStatus = .healthy
        } else {
            overallStatus = .offline
        }
    }
    
    // MARK: - Persistence
    
    private func loadMetrics() {
        if let data = userDefaults.data(forKey: metricsKey),
           let decoded = try? JSONDecoder().decode([SyncTopic: SyncMetrics].self, from: data) {
            metrics = decoded
        }
        
        if let data = userDefaults.data(forKey: subscriptionsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            subscriptions = decoded
        }
        
        updateOverallStatus()
    }
    
    private func saveMetrics() {
        if let encoded = try? JSONEncoder().encode(metrics) {
            userDefaults.set(encoded, forKey: metricsKey)
        }
    }
    
    private func saveSubscriptions() {
        if let encoded = try? JSONEncoder().encode(subscriptions) {
            userDefaults.set(encoded, forKey: subscriptionsKey)
        }
    }
    
    // MARK: - Public Accessors
    
    public func getMetrics(for topic: SyncTopic) -> SyncMetrics? {
        return metrics[topic]
    }
    
    public func getLastSyncTime(for topic: SyncTopic) -> Date? {
        return metrics[topic]?.lastSyncTime
    }
    
    public func getLastSuccessTime(for topic: SyncTopic) -> Date? {
        return metrics[topic]?.lastSuccessTime
    }
    
    public func getStatus(for topic: SyncTopic) -> SyncHealthStatus {
        return metrics[topic]?.status ?? .offline
    }
    
    public func getHealthSummary() -> String {
        var summary = "Sync Health Summary:\n"
        
        for topic in SyncTopic.allCases {
            if let metric = metrics[topic] {
                let timeAgo = metric.lastSuccessTime.map { formatTimeAgo($0) } ?? "Never"
                summary += "\(metric.healthEmoji) \(topic.rawValue.capitalized): \(timeAgo)\n"
            }
        }
        
        summary += "\n📡 Subscriptions: \(subscriptions.count) active"
        summary += "\n💓 Last heartbeat: \(lastHeartbeat.map { formatTimeAgo($0) } ?? "Never")"
        
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
        metrics.removeAll()
        subscriptions.removeAll()
        overallStatus = .offline
        lastHeartbeat = nil
        
        userDefaults.removeObject(forKey: metricsKey)
        userDefaults.removeObject(forKey: subscriptionsKey)
        
        debugLog("[SyncHealth] 🔄 Health monitor reset")
    }
    
    // MARK: - Async Accessors for UI
    
    public func getAllMetrics() async -> [SyncHealthMetric] {
        return metrics.values.map { metric in
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
        return subscriptions
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
