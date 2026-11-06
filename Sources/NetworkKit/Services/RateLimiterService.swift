// MARK: - NetworkKit/Services/RateLimiterService.swift

import Foundation
import WaanguCoreKit
// MARK: - Protocol

public protocol RateLimiterService: Sendable {
    func shouldAllowRequest(endpointKey: String, policy: RateLimitPolicy) async -> Bool
}

// MARK: - Implementation

public actor RateLimiterServiceImpl: RateLimiterService {

    private struct Bucket {
        var timestamps: [Date] = []
    }

    private var buckets: [String: Bucket] = [:]
    private let logger: AppLogger

    public init(logger: AppLogger) {
        self.logger = logger
    }

    public func shouldAllowRequest(
        endpointKey: String,
        policy: RateLimitPolicy
    ) async -> Bool {
        // Court-circuit si aucune limitation configurée
        guard policy.maxRequests != .max else { return true }

        let now = Date()
        var bucket = buckets[endpointKey] ?? Bucket()

        // Nettoyage fenêtre glissante
        bucket.timestamps.removeAll {
            now.timeIntervalSince($0) > policy.perSeconds
        }

        if bucket.timestamps.count >= policy.maxRequests {
            let retryIn = policy.perSeconds - now.timeIntervalSince(bucket.timestamps.first!)
            await logger.log(
                "[RateLimiter] ⛔ \(endpointKey) blocked — retry in \(String(format: "%.2f", retryIn))s",
                level: .warning
            )
            return false
        }

        bucket.timestamps.append(now)
        buckets[endpointKey] = bucket

        await logger.log(
            "[RateLimiter] ✅ \(endpointKey) (\(bucket.timestamps.count)/\(policy.maxRequests))",
            level: .debug
        )
        return true
    }
}
