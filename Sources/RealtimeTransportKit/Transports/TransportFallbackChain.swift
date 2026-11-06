// MARK: - RealtimeKit/Transports/TransportFallbackChain.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Enchaîne plusieurs transports avec fallback automatique.
//           Si le transport principal échoue après N tentatives,
//           le suivant est essayé — transparent pour le RealtimeClient.
//
// Note importante :
//   Le fallback MQTT TCP → MQTT WebSocket est géré INTERNEMENT
//   par MQTTTransport (enableWebsockets). Ce fichier gère le fallback
//   entre des transports FONDAMENTALEMENT différents
//   (ex: MQTT → WebSocket standalone → SSE).
//
// Design  : Actor. Implémente RealtimeTransport.
//           Le RealtimeClient voit un seul transport.

import Foundation
import WaanguCoreKit

// MARK: - TransportFallbackChain

actor TransportFallbackChain: RealtimeTransport {

    // MARK: - Identity

    nonisolated let transportName: String = "FallbackChain"
    nonisolated let transportType: RealtimeTransportType = .mqtt

    // MARK: - Chain

    private let transports: [any RealtimeTransport]
    private var activeTransport: (any RealtimeTransport)?
    private var activeIndex: Int = 0

    // MARK: - Config

    private let attemptsPerTransport: Int
    private let fallbackTimeout: TimeInterval

    // MARK: - Streams

    private var connectionContinuation: AsyncStream<TransportConnectionEvent>.Continuation?
    private var messageContinuation: AsyncStream<RawTransportMessage>.Continuation?
    private var connectionBridgeTask: Task<Void, Never>?
    private var messageBridgeTask: Task<Void, Never>?

    // MARK: - Metrics

    private let metricsDelegate: (any RealtimeMetricsDelegate)?
    private(set) var fallbackHistory: [(from: String, to: String, reason: String)] = []

    // MARK: - Init

    init(
        config: TransportFallbackConfig,
        factory: (TransportType) -> any RealtimeTransport,
        metricsDelegate: (any RealtimeMetricsDelegate)? = nil
    ) {
        self.transports = config.chain.map { factory($0) }
        self.attemptsPerTransport = config.attemptsPerTransport
        self.fallbackTimeout = config.fallbackTimeout
        self.metricsDelegate = metricsDelegate
    }

    // MARK: - RealtimeTransport — Connection

    var isConnected: Bool {
        get async {
            guard let active = activeTransport else { return false }
            return await active.isConnected
        }
    }

    func connect(config: RealtimeTransportConfig) async throws {
        for (index, transport) in transports.enumerated() {
            for attempt in 1...attemptsPerTransport {
                do {
                    try await connectWithTimeout(
                        transport: transport,
                        config: config,
                        timeout: fallbackTimeout
                    )

                    // Succès.
                    activeTransport = transport
                    activeIndex = index
                    startBridging(transport: transport)

                    // Notifier si c'est un fallback.
                    if index > 0 {
                        let prev = transports[index - 1].transportName
                        let curr = transport.transportName
                        recordFallback(from: prev, to: curr, reason: "Primary failed")
                    }
                    return

                } catch {
                    #if DEBUG
                    print("[FallbackChain] \(transport.transportName) attempt \(attempt)/\(attemptsPerTransport): \(error.localizedDescription)")
                    #endif
                    if attempt < attemptsPerTransport {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
        }

        // Tous les transports ont échoué.
        connectionContinuation?.yield(.disconnected(error: "All transports failed", isRecoverable: false))
        throw RealtimeError.allTransportsFailed
    }

    func disconnect(reason: DisconnectReason) async throws {
        stopBridging()
        try? await activeTransport?.disconnect(reason: reason)
        activeTransport = nil
    }

    func connectionStateStream() async -> AsyncStream<TransportConnectionEvent> {
        connectionContinuation?.finish()
        let (stream, cont) = AsyncStream<TransportConnectionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(10)
        )
        connectionContinuation = cont
        if let active = activeTransport {
            startBridging(transport: active)
        }
        return stream
    }

    // MARK: - RealtimeTransport — Pub/Sub/Publish

    func subscribe(topic: String, qos: RealtimeQoS) async throws {
        guard let active = activeTransport else { throw RealtimeError.notConnected }
        try await active.subscribe(topic: topic, qos: qos)
    }

    func unsubscribe(topic: String) async throws {
        try? await activeTransport?.unsubscribe(topic: topic)
    }

    func publish(data: Data, to topic: String, qos: RealtimeQoS, messageId: MessageID) async throws {
        guard let active = activeTransport else { throw RealtimeError.notConnected }
        try await active.publish(data: data, to: topic, qos: qos, messageId: messageId)
    }

    func incomingMessages() async -> AsyncStream<RawTransportMessage> {
        messageContinuation?.finish()
        let (stream, cont) = AsyncStream<RawTransportMessage>.makeStream(bufferingPolicy: .bufferingNewest(100))
        messageContinuation = cont
        return stream
    }

    func updateHeartbeatInterval(_ interval: TimeInterval?) async {
        await activeTransport?.updateHeartbeatInterval(interval)
    }

    func reauthenticate(with credentials: RealtimeCredentials) async throws -> Bool {
        guard let active = activeTransport else { return false }
        return try await active.reauthenticate(with: credentials)
    }

    // MARK: - Private — Stream Bridging

    private func startBridging(transport: any RealtimeTransport) {
        stopBridging()

        connectionBridgeTask = Task { [weak self] in
            guard let self else { return }
            for await event in await transport.connectionStateStream() {
                guard !Task.isCancelled else { break }
                await self.connectionContinuation?.yield(event)
            }
        }

        messageBridgeTask = Task { [weak self] in
            guard let self else { return }
            for await message in await transport.incomingMessages() {
                guard !Task.isCancelled else { break }
                await self.messageContinuation?.yield(message)
            }
        }
    }

    private func stopBridging() {
        connectionBridgeTask?.cancel()
        messageBridgeTask?.cancel()
        connectionBridgeTask = nil
        messageBridgeTask = nil
    }

    // MARK: - Private — Helpers

    private func connectWithTimeout(
        transport: any RealtimeTransport,
        config: RealtimeTransportConfig,
        timeout: TimeInterval
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await transport.connect(config: config) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RealtimeError.connectionFailed(
                    reason: "\(transport.transportName) timed out after \(Int(timeout))s"
                )
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func recordFallback(from: String, to: String, reason: String) {
        fallbackHistory.append((from: from, to: to, reason: reason))
        Task { [metricsDelegate] in
            await metricsDelegate?.didFallbackTransport(from: from, to: to, reason: reason)
        }
        #if DEBUG
        print("[FallbackChain] Fallback: \(from) → \(to) (\(reason))")
        #endif
    }
}
