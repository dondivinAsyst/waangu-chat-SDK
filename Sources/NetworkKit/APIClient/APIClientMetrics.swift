// MARK: - NetworkKit/APIClient/APIClientMetrics.swift

import Foundation
import WaanguCoreKit

// MARK: - PerformanceMetrics

/// Métriques internes d'APIClient.
/// Exposées via `APIPerformanceMetrics` (CoreKit) dans `getPerformanceMetrics()`.
struct APIClientMetrics {
    var totalRequests: Int = 0
    var successfulRequests: Int = 0
    var failedRequests: Int = 0
    var averageResponseTime: TimeInterval = 0
    var currentConcurrentRequests: Int = 0
    var peakConcurrentRequests: Int = 0
    var timeoutRate: Double = 0
    var errorByType: [String: Int] = [:]
    var circuitBreakerBlocks: Int = 0
    var rateLimitedRequests: Int = 0
    var timeoutCount: Int = 0

    private static let maxSamples = 100
    private var responseTimes: [TimeInterval] = []

    var successRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(successfulRequests) / Double(totalRequests) * 100
    }

    var p95ResponseTime: TimeInterval {
        guard !responseTimes.isEmpty else { return 0 }
        let sorted = responseTimes.sorted()
        let index = Int(ceil(Double(sorted.count) * 0.95)) - 1
        return sorted[max(0, index)]
    }

    mutating func appendResponseTime(_ duration: TimeInterval) {
        if responseTimes.count >= Self.maxSamples { responseTimes.removeFirst() }
        responseTimes.append(duration)
        averageResponseTime = responseTimes.reduce(0, +) / Double(responseTimes.count)
    }

    /// Conversion vers le type public CoreKit.
    func toPublic() -> APIPerformanceMetrics {
        APIPerformanceMetrics(
            totalRequests: totalRequests,
            successCount: successfulRequests,
            failureCount: failedRequests,
            averageDuration: averageResponseTime,
            rateLimitedCount: rateLimitedRequests,
            circuitBreakerBlockCount: circuitBreakerBlocks
        )
    }
}

// MARK: - MetricsCollector

/// Acteur dédié aux métriques.
/// Isolé d'APIClient pour éviter la contention lors des pics de requêtes.
actor MetricsCollector {

    private(set) var metrics = APIClientMetrics()

    func recordRequestStart() {
        metrics.totalRequests += 1
        metrics.currentConcurrentRequests += 1
        if metrics.currentConcurrentRequests > metrics.peakConcurrentRequests {
            metrics.peakConcurrentRequests = metrics.currentConcurrentRequests
        }
    }

    func recordRequestEnd() {
        metrics.currentConcurrentRequests = max(0, metrics.currentConcurrentRequests - 1)
    }

    func recordSuccess(duration: TimeInterval) {
        metrics.successfulRequests += 1
        metrics.appendResponseTime(duration)
    }

    func recordFailure(errorType: String, isTimeout: Bool) {
        metrics.failedRequests += 1
        metrics.errorByType[errorType, default: 0] += 1
        if isTimeout {
            metrics.timeoutCount += 1
            metrics.timeoutRate = Double(metrics.timeoutCount) / Double(max(1, metrics.failedRequests))
        }
    }

    func recordRateLimited()        { metrics.rateLimitedRequests += 1 }
    func recordCircuitBreakerBlock() { metrics.circuitBreakerBlocks += 1 }

    func snapshot() -> APIClientMetrics { metrics }
}
