import Foundation

/// Runtime performance metrics collection and monitoring
/// Tracks app performance, memory usage, and custom metrics
public actor RuntimeMetric {
    
    public static let shared = RuntimeMetric()
    
    private var metrics: [String: MetricValue] = [:]
    private var timers: [String: Date] = [:]
    private var counters: [String: Int] = [:]
    private var gauges: [String: Double] = [:]
    private var histograms: [String: [Double]] = [:]
    private var observers: [UUID: @Sendable (MetricEvent) async -> Void] = [:]
    
    private let maxHistogramSize = 1000
    
    private init() {}
    
    // MARK: - Timers
    
    /// Start a timer for measuring duration
    public func startTimer(_ name: String) {
        timers[name] = Date()
    }
    
    /// Stop a timer and record the duration
    @discardableResult
    public func stopTimer(_ name: String) -> TimeInterval? {
        guard let startTime = timers[name] else { return nil }
        
        let duration = Date().timeIntervalSince(startTime)
        timers.removeValue(forKey: name)
        
        // Record as histogram
        recordHistogram(name, value: duration)
        
        // Notify observers
        Task {
            await notifyObservers(.timerStopped(name, duration))
        }
        
        return duration
    }
    
    /// Measure execution time of a block
    @discardableResult
    public func measure<T>(
        _ name: String,
        block: () async throws -> T
    ) async rethrows -> T {
        let startTime = Date()
        let result = try await block()
        let duration = Date().timeIntervalSince(startTime)
        
        recordHistogram(name, value: duration)
        await notifyObservers(.timerStopped(name, duration))
        
        return result
    }
    
    // MARK: - Counters
    
    /// Increment a counter
    public func incrementCounter(_ name: String, by value: Int = 1) {
        let newValue = (counters[name] ?? 0) + value
        counters[name] = newValue
        
        Task {
            await notifyObservers(.counterUpdated(name, newValue))
        }
    }
    
    /// Decrement a counter
    public func decrementCounter(_ name: String, by value: Int = 1) {
        let newValue = (counters[name] ?? 0) - value
        counters[name] = max(0, newValue)
        
        Task {
            await notifyObservers(.counterUpdated(name, newValue))
        }
    }
    
    /// Get counter value
    public func getCounter(_ name: String) -> Int {
        counters[name] ?? 0
    }
    
    /// Reset counter
    public func resetCounter(_ name: String) {
        counters[name] = 0
    }
    
    // MARK: - Gauges
    
    /// Set a gauge value (current measurement)
    public func setGauge(_ name: String, value: Double) {
        gauges[name] = value
        
        Task {
            await notifyObservers(.gaugeUpdated(name, value))
        }
    }
    
    /// Get gauge value
    public func getGauge(_ name: String) -> Double? {
        gauges[name]
    }
    
    // MARK: - Histograms
    
    /// Record a value in a histogram
    public func recordHistogram(_ name: String, value: Double) {
        var values = histograms[name] ?? []
        values.append(value)
        
        // Trim if too large
        if values.count > maxHistogramSize {
            values.removeFirst(values.count - maxHistogramSize)
        }
        
        histograms[name] = values
        
        Task {
            await notifyObservers(.histogramRecorded(name, value))
        }
    }
    
    /// Get histogram statistics
    public func getHistogramStats(_ name: String) -> HistogramStats? {
        guard let values = histograms[name], !values.isEmpty else {
            return nil
        }
        
        let sorted = values.sorted()
        let count = values.count
        let sum = values.reduce(0, +)
        let mean = sum / Double(count)
        
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(count)
        let stdDev = sqrt(variance)
        
        let p50Index = Int(Double(count) * 0.50)
        let p95Index = Int(Double(count) * 0.95)
        let p99Index = Int(Double(count) * 0.99)
        
        return HistogramStats(
            count: count,
            sum: sum,
            mean: mean,
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            stdDev: stdDev,
            p50: sorted[p50Index],
            p95: sorted[p95Index],
            p99: sorted[p99Index]
        )
    }
    
    // MARK: - System Metrics
    
    /// Get current memory usage
    public func getMemoryUsage() -> MemoryUsage {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        let usedMB = result == KERN_SUCCESS ? Double(info.resident_size) / 1024 / 1024 : 0
        
        return MemoryUsage(
            usedMB: usedMB,
            timestamp: Date()
        )
    }
    
    /// Record current memory usage
    public func recordMemoryUsage() {
        let usage = getMemoryUsage()
        setGauge("memory_usage_mb", value: usage.usedMB)
    }
    
    /// Get CPU usage (approximate)
    public func getCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList = UnsafeMutablePointer<thread_act_t>(bitPattern: 0)
        var threadsCount = mach_msg_type_number_t(0)
        
        let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)
        
        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                
                if infoResult == KERN_SUCCESS {
                    let threadBasicInfo = threadInfo
                    if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                        totalUsageOfCPU += Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                    }
                }
            }
            
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        }
        
        return totalUsageOfCPU
    }
    
    /// Record current CPU usage
    public func recordCPUUsage() {
        let usage = getCPUUsage()
        setGauge("cpu_usage_percent", value: usage)
    }
    
    // MARK: - Snapshots
    
    /// Get all metrics snapshot
    public func getSnapshot() -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: Date(),
            counters: counters,
            gauges: gauges,
            histograms: histograms.mapValues { values in
                getHistogramStats(values) ?? HistogramStats.empty
            },
            memoryUsage: getMemoryUsage(),
            cpuUsage: getCPUUsage()
        )
    }
    
    /// Reset all metrics
    public func reset() {
        metrics.removeAll()
        timers.removeAll()
        counters.removeAll()
        gauges.removeAll()
        histograms.removeAll()
    }
    
    /// Reset specific metric type
    public func reset(_ type: MetricType) {
        switch type {
        case .counter:
            counters.removeAll()
        case .gauge:
            gauges.removeAll()
        case .histogram:
            histograms.removeAll()
        case .timer:
            timers.removeAll()
        }
    }
    
    // MARK: - Observers
    
    /// Add observer for metric events
    public func addObserver(_ observer: @escaping @Sendable (MetricEvent) async -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }
    
    /// Remove observer
    public func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }
    
    // MARK: - Private Helpers
    
    private func notifyObservers(_ event: MetricEvent) async {
        for observer in observers.values {
            await observer(event)
        }
    }
    
    private func getHistogramStats(_ values: [Double]) -> HistogramStats? {
        guard !values.isEmpty else { return nil }
        
        let sorted = values.sorted()
        let count = values.count
        let sum = values.reduce(0, +)
        let mean = sum / Double(count)
        
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(count)
        let stdDev = sqrt(variance)
        
        let p50Index = Int(Double(count) * 0.50)
        let p95Index = Int(Double(count) * 0.95)
        let p99Index = Int(Double(count) * 0.99)
        
        return HistogramStats(
            count: count,
            sum: sum,
            mean: mean,
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            stdDev: stdDev,
            p50: sorted[p50Index],
            p95: sorted[p95Index],
            p99: sorted[p99Index]
        )
    }
}

// MARK: - Models

/// Metric value types
public enum MetricValue: Sendable {
    case counter(Int)
    case gauge(Double)
    case histogram([Double])
    case timer(TimeInterval)
}

/// Metric types
public enum MetricType: Sendable {
    case counter
    case gauge
    case histogram
    case timer
}

/// Metric events
public enum MetricEvent: Sendable {
    case counterUpdated(String, Int)
    case gaugeUpdated(String, Double)
    case histogramRecorded(String, Double)
    case timerStopped(String, TimeInterval)
}

/// Histogram statistics
public struct HistogramStats: Sendable {
    public let count: Int
    public let sum: Double
    public let mean: Double
    public let min: Double
    public let max: Double
    public let stdDev: Double
    public let p50: Double
    public let p95: Double
    public let p99: Double
    
    public static let empty = HistogramStats(
        count: 0, sum: 0, mean: 0, min: 0, max: 0,
        stdDev: 0, p50: 0, p95: 0, p99: 0
    )
}

/// Memory usage information
public struct MemoryUsage: Sendable {
    public let usedMB: Double
    public let timestamp: Date
}

/// Complete metrics snapshot
public struct MetricsSnapshot: Sendable {
    public let timestamp: Date
    public let counters: [String: Int]
    public let gauges: [String: Double]
    public let histograms: [String: HistogramStats]
    public let memoryUsage: MemoryUsage
    public let cpuUsage: Double
}

// MARK: - Convenience Extensions

public extension RuntimeMetric {
    /// Common metric names
    enum CommonMetrics {
        public static let apiCallDuration = "api_call_duration"
        public static let apiCallCount = "api_call_count"
        public static let apiErrorCount = "api_error_count"
        public static let messagesSent = "messages_sent"
        public static let messagesReceived = "messages_received"
        public static let screenLoadTime = "screen_load_time"
        public static let databaseQueryTime = "database_query_time"
        public static let imageLoadTime = "image_load_time"
        public static let activeUsers = "active_users"
        public static let memoryUsage = "memory_usage_mb"
        public static let cpuUsage = "cpu_usage_percent"
    }
    
    /// Record API call metrics
    func recordAPICall(
        endpoint: String,
        duration: TimeInterval,
        success: Bool
    ) {
        recordHistogram("\(CommonMetrics.apiCallDuration)_\(endpoint)", value: duration)
        incrementCounter(CommonMetrics.apiCallCount)
        
        if !success {
            incrementCounter(CommonMetrics.apiErrorCount)
        }
    }
    
    /// Record screen load time
    func recordScreenLoad(screen: String, duration: TimeInterval) {
        recordHistogram("\(CommonMetrics.screenLoadTime)_\(screen)", value: duration)
    }
}

// MARK: - Usage Examples

/*
 Example 1: Measure function execution time
 
 let result = await RuntimeMetric.shared.measure("fetch_messages") {
     try await messageService.fetchMessages()
 }
 
 Example 2: Manual timer
 
 await RuntimeMetric.shared.startTimer("image_processing")
 // ... do work ...
 let duration = await RuntimeMetric.shared.stopTimer("image_processing")
 print("Processing took \(duration ?? 0)s")
 
 Example 3: Counter for events
 
 await RuntimeMetric.shared.incrementCounter("messages_sent")
 await RuntimeMetric.shared.incrementCounter("api_calls")
 
 let messageCount = await RuntimeMetric.shared.getCounter("messages_sent")
 print("Sent \(messageCount) messages")
 
 Example 4: Gauge for current values
 
 await RuntimeMetric.shared.setGauge("active_connections", value: 5)
 await RuntimeMetric.shared.setGauge("queue_size", value: 42)
 
 Example 5: Get histogram statistics
 
 if let stats = await RuntimeMetric.shared.getHistogramStats("api_call_duration") {
     print("Mean: \(stats.mean)s")
     print("P95: \(stats.p95)s")
     print("P99: \(stats.p99)s")
 }
 
 Example 6: Monitor system metrics
 
 await RuntimeMetric.shared.recordMemoryUsage()
 await RuntimeMetric.shared.recordCPUUsage()
 
 let memory = await RuntimeMetric.shared.getMemoryUsage()
 print("Memory: \(memory.usedMB) MB")
 
 Example 7: Get complete snapshot
 
 let snapshot = await RuntimeMetric.shared.getSnapshot()
 print("Counters: \(snapshot.counters)")
 print("Memory: \(snapshot.memoryUsage.usedMB) MB")
 print("CPU: \(snapshot.cpuUsage)%")
 
 Example 8: Monitor metrics
 
 let observerId = await RuntimeMetric.shared.addObserver { event in
     switch event {
     case .timerStopped(let name, let duration):
         if duration > 1.0 {
             print("⚠️ Slow operation: \(name) took \(duration)s")
         }
     case .counterUpdated(let name, let value):
         if name == "api_error_count" && value > 10 {
             print("⚠️ High error rate: \(value) errors")
         }
     default:
         break
     }
 }
 */
