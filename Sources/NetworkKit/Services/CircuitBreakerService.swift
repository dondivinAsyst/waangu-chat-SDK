// MARK: - NetworkKit/Services/CircuitBreakerService.swift

import Foundation
import WaanguCoreKit
// MARK: - Protocol

public protocol CircuitBreakerService: Sendable {
    func shouldAllowRequest(endpointKey: String, profile: CircuitBreakerProfile) async -> Bool
    func recordSuccess(endpointKey: String, profile: CircuitBreakerProfile) async
    func recordFailure(endpointKey: String, profile: CircuitBreakerProfile) async
    func reset(endpointKey: String) async
    func setProfile(_ profile: CircuitBreakerProfile, forEndpoint endpointKey: String) async
    func removeProfile(forEndpoint endpointKey: String) async
}

// MARK: - Implementation

public actor CircuitBreakerServiceImpl: CircuitBreakerService {

    // MARK: - Internal State

    private struct CircuitBreakerState {
        var failureCount: Int = 0
        var successCount: Int = 0
        var lastFailure: Date?
        var openedAt: Date?
        var phase: Phase = .closed

        enum Phase {
            case closed
            case open
            case halfOpen
        }
    }

    // MARK: - Mutable Config

    public struct MutableConfig {
        public var defaultProfile: CircuitBreakerProfile
        public var endpointProfiles: [String: CircuitBreakerProfile]

        public init(defaultProfile: CircuitBreakerProfile = .standard) {
            self.defaultProfile = defaultProfile
            self.endpointProfiles = [:]
        }
    }

    // MARK: - Properties

    private var states: [String: CircuitBreakerState] = [:]
    private let logger: AppLogger
    private var config: MutableConfig

    // MARK: - Init

    public init(logger: AppLogger) {
        self.logger = logger
        self.config = MutableConfig()
    }

    // MARK: - Profile Management

    public func setProfile(_ profile: CircuitBreakerProfile, forEndpoint endpointKey: String) async {
        config.endpointProfiles[endpointKey] = profile
        await logger.log("[CB] \(endpointKey) — profile: \(profile)", level: .debug)
    }

    public func removeProfile(forEndpoint endpointKey: String) async {
        config.endpointProfiles.removeValue(forKey: endpointKey)
    }

    // MARK: - CircuitBreakerService

    public func shouldAllowRequest(
        endpointKey: String,
        profile: CircuitBreakerProfile = .standard
    ) async -> Bool {
        if case .disabled = profile { return true }

        let policy = CircuitBreakerPolicy.from(profile)
        var state  = states[endpointKey] ?? CircuitBreakerState()

        switch state.phase {
        case .closed:
            return true

        case .open:
            guard let lastFailure = state.lastFailure else {
                state.phase = .closed
                states[endpointKey] = state
                return true
            }
            let elapsed = Date().timeIntervalSince(lastFailure)
            if elapsed >= policy.resetTimeout {
                state.phase = .halfOpen
                state.successCount = 0
                states[endpointKey] = state
                await logger.log("[CB] \(endpointKey) OPEN → HALF-OPEN", level: .info)
                return true
            }
            await logger.log(
                "[CB] \(endpointKey) OPEN — retry in \(String(format: "%.1f", policy.resetTimeout - elapsed))s",
                level: .warning
            )
            return false

        case .halfOpen:
            if state.successCount >= policy.halfOpenMaxRequests {
                await logger.log("[CB] \(endpointKey) HALF-OPEN limit reached", level: .warning)
                return false
            }
            state.successCount += 1
            states[endpointKey] = state
            return true
        }
    }

    public func recordSuccess(
        endpointKey: String,
        profile: CircuitBreakerProfile = .standard
    ) async {
        if case .disabled = profile { return }
        var state  = states[endpointKey] ?? CircuitBreakerState()
        let policy = CircuitBreakerPolicy.from(profile)

        switch state.phase {
        case .closed:
            state.failureCount = 0
        case .halfOpen:
            state.successCount += 1
            if state.successCount >= policy.halfOpenMaxRequests {
                state.phase = .closed
                state.failureCount = 0
                state.successCount = 0
                await logger.log("[CB] \(endpointKey) HALF-OPEN → CLOSED", level: .info)
            }
        case .open:
            break
        }
        states[endpointKey] = state
    }

    public func recordFailure(
        endpointKey: String,
        profile: CircuitBreakerProfile = .standard
    ) async {
        if case .disabled = profile { return }
        var state  = states[endpointKey] ?? CircuitBreakerState()
        let policy = CircuitBreakerPolicy.from(profile)
        state.lastFailure = Date()

        switch state.phase {
        case .closed:
            state.failureCount += 1
            if state.failureCount >= policy.failureThreshold {
                state.phase = .open
                state.openedAt = Date()
                await logger.log("[CB] \(endpointKey) CLOSED → OPEN", level: .warning)
            }
        case .halfOpen:
            state.phase = .open
            state.failureCount = 1
            state.successCount = 0
            state.openedAt = Date()
            await logger.log("[CB] \(endpointKey) HALF-OPEN → OPEN (failure)", level: .warning)
        case .open:
            break
        }
        states[endpointKey] = state
    }

    public func reset(endpointKey: String) async {
        states[endpointKey] = CircuitBreakerState()
        await logger.log("[CB] \(endpointKey) — manual reset", level: .info)
    }

    // MARK: - Debug

    public func clearAll() async {
        states.removeAll()
    }
}
