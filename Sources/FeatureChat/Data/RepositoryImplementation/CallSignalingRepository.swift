//
//  CallSignalingRepository.swift
//  FeatureChat
//
//  Publishes call commands and surfaces inbound call events.
//
//  Every payload carries `sessionId`; the server answers UNAUTHENTICATED
//  without it, so a missing session fails fast here rather than producing a
//  call that silently never rings.
//

import Foundation
import WaanguCoreKit

actor CallSignalingRepository: CallSignalingRepositoryProtocol {

    enum CallSignalingError: LocalizedError {
        case missingSession
        case missingUser
        case notConnected
        case malformedParameters(String)
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .missingSession:
                return "No active chat session — the call cannot be signalled."
            case .missingUser:
                return "No signed-in user — the call cannot be signalled."
            case .notConnected:
                return "No connection — the call could not be placed."
            case .malformedParameters(let detail):
                return "The media parameters could not be encoded: \(detail)"
            case .timedOut(let what):
                return "The server never answered \(what)."
            }
        }
    }

    private let realtime: any RealtimeClientProtocol
    private let currentUserId: @Sendable () -> String
    private let currentUserName: @Sendable () -> String
    private let currentUserPhone: @Sendable () -> String
    private let sessionId: @Sendable () -> String
    private let deviceIdProvider: @Sendable () -> String

    private let subscriptions = SubscriptionGroup()

    init(
        realtime: any RealtimeClientProtocol,
        deviceInfoProvider: any DeviceInfoProvidingProtocol,
        currentUserId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.currentUid },
        currentUserName: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.userName },
        currentUserPhone: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.userPhoneNumber },
        sessionId: @escaping @Sendable () -> String = { CurrentSessionInfo.shared.sessionId }
    ) {
        self.realtime = realtime
        self.currentUserId = currentUserId
        self.currentUserName = currentUserName
        self.currentUserPhone = currentUserPhone
        self.sessionId = sessionId
        // Captured once: the id is stable per install, and the closure keeps the
        // provider out of this actor's isolation.
        let capturedDeviceId = deviceInfoProvider.captureDeviceContext().deviceId
        self.deviceIdProvider = { capturedDeviceId }
    }

    // MARK: - Credentials

    private func credentials() throws -> (session: String, peer: String) {
        let session = sessionId()
        guard !session.isEmpty else { throw CallSignalingError.missingSession }
        let peer = currentUserId()
        guard !peer.isEmpty else { throw CallSignalingError.missingUser }
        return (session, peer)
    }

    private var me: CallParticipantDTO {
        CallParticipantDTO(
            userId: currentUserId(),
            username: currentUserName(),
            phone: currentUserPhone()
        )
    }

    // MARK: - Setup

    func sendOffer(
        roomId: String,
        conversationId: String?,
        isVideo: Bool,
        participants: [CallParticipantDTO]
    ) async throws {
        let (session, peer) = try credentials()
        try await prepareForOutboundSignaling()

        // The contract expects the caller in the participant list alongside the
        // callees.
        var everyone = participants
        if !everyone.contains(where: { $0.userId == peer }) {
            everyone.insert(me, at: 0)
        }

        try await realtime.publish(
            CallOfferDTO(
                sessionId: session,
                deviceId: deviceIdProvider(),
                roomId: roomId,
                peerId: peer,
                conversationId: conversationId,
                type: isVideo ? "video" : "audio",
                participants: everyone
            ),
            to: ChatMQTTTopics.In.callOffer,
            qos: .atLeastOnce,
            priority: .high
        )
    }

    func sendJoin(roomId: String) async throws {
        let (session, peer) = try credentials()
        try await prepareForOutboundSignaling()
        try await realtime.publish(
            CallJoinDTO(
                sessionId: session,
                deviceId: deviceIdProvider(),
                roomId: roomId,
                peerId: peer,
                user: me
            ),
            to: ChatMQTTTopics.In.callJoin,
            qos: .atLeastOnce,
            priority: .high
        )
    }

    func sendReject(roomId: String, reason: String) async throws {
        let (session, peer) = try credentials()
        try await prepareForOutboundSignaling()
        try await realtime.publish(
            CallRejectDTO(sessionId: session, roomId: roomId, userId: peer, reason: reason),
            to: ChatMQTTTopics.In.callReject,
            qos: .atLeastOnce,
            priority: .high
        )
    }

    func sendDisconnect(roomId: String) async throws {
        let (session, peer) = try credentials()
        try await prepareForOutboundSignaling()
        try await realtime.publish(
            CallDisconnectDTO(sessionId: session, roomId: roomId, peerId: peer),
            to: ChatMQTTTopics.In.callDisconnect,
            qos: .atLeastOnce,
            priority: .high
        )
    }

    /// Connects realtime if needed, then ensures the call inbox is listening.
    func prepareForOutboundSignaling() async throws {
        try await ensureRealtimeConnected()
        await ensureInboundPump()
    }

    /// Waits out an in-flight reconnect, or kicks `connect()` when fully down.
    private func ensureRealtimeConnected() async throws {
        if await realtime.connectionState.isConnected { return }

        if await realtime.connectionState.isTransitioning {
            try await waitUntilRealtimeConnected(timeout: .seconds(10))
            return
        }

        do {
            try await realtime.connect()
        } catch {
            // A parallel wake (VoIP push, foreground) may already be connecting.
            if await realtime.connectionState.isConnected { return }
            if await realtime.connectionState.isTransitioning {
                try await waitUntilRealtimeConnected(timeout: .seconds(10))
                return
            }
            throw error
        }

        guard await realtime.connectionState.isConnected else {
            throw CallSignalingError.notConnected
        }
    }

    private func waitUntilRealtimeConnected(timeout: Duration) async throws {
        if await realtime.connectionState.isConnected { return }

        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { [realtime] in
                for await state in realtime.observeConnectionState() {
                    if state.isConnected { return true }
                }
                return false
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return false
            }
            let connected = try await group.next() ?? false
            group.cancelAll()
            guard connected else { throw CallSignalingError.notConnected }
        }
    }

    // MARK: - In-call state

    func sendMute(roomId: String, isMuted: Bool) async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallMuteDTO(sessionId: session, roomId: roomId, peerId: peer, isMuted: isMuted),
            to: ChatMQTTTopics.In.callMute,
            qos: .atLeastOnce,
            priority: .normal
        )
    }

    func sendVideo(roomId: String, isVideoOff: Bool) async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallVideoDTO(sessionId: session, roomId: roomId, peerId: peer, isVideoOff: isVideoOff),
            to: ChatMQTTTopics.In.callVideo,
            qos: .atLeastOnce,
            priority: .normal
        )
    }

    // MARK: - Conference features (§16)

    func sendHandRaise(roomId: String, callId: String?) async throws {
        try await publishHand(to: ChatMQTTTopics.In.callHandRaise, roomId: roomId, callId: callId)
    }

    func sendHandLower(roomId: String, callId: String?) async throws {
        try await publishHand(to: ChatMQTTTopics.In.callHandLower, roomId: roomId, callId: callId)
    }

    func sendHandAck(roomId: String, callId: String?, targetUserId: String) async throws {
        try await publishHand(
            to: ChatMQTTTopics.In.callHandAck,
            roomId: roomId,
            callId: callId,
            targetUserId: targetUserId
        )
    }

    func sendReaction(roomId: String, reaction: String) async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallReactionDTO(sessionId: session, roomId: roomId, peerId: peer, reaction: reaction),
            to: ChatMQTTTopics.In.callReaction,
            qos: .atLeastOnce,
            priority: .normal
        )
    }

    /// The three hand topics differ only by destination and whether the ack's
    /// subject rides along.
    private func publishHand(
        to topic: RealtimeTopic,
        roomId: String,
        callId: String?,
        targetUserId: String? = nil
    ) async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallHandDTO(
                sessionId: session,
                roomId: roomId,
                peerId: peer,
                callId: callId,
                targetUserId: targetUserId
            ),
            to: topic,
            qos: .atLeastOnce,
            priority: .normal
        )
    }

    func sendInvitePeers(
        roomId: String,
        isVideo: Bool,
        participants: [CallParticipantDTO]
    ) async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallInvitePeersDTO(
                sessionId: session,
                roomId: roomId,
                peerId: peer,
                type: isVideo ? "video" : "audio",
                participants: participants
            ),
            to: ChatMQTTTopics.In.callInvitePeers,
            qos: .atLeastOnce,
            priority: .high
        )
    }

    // MARK: - Keep-alive and recovery

    func sendScreenShareStart(roomId: String) async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallScreenShareDTO(sessionId: session, peerId: peer, roomId: roomId),
            to: ChatMQTTTopics.In.callScreenShareStart,
            qos: .fireAndForget,
            priority: .high
        )
    }

    func sendScreenShareStop(roomId: String) async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallScreenShareDTO(sessionId: session, peerId: peer, roomId: roomId),
            to: ChatMQTTTopics.In.callScreenShareStop,
            qos: .fireAndForget,
            priority: .high
        )
    }

    func sendHeartbeat(roomId: String) async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallHeartbeatDTO(sessionId: session, peerId: peer, roomId: roomId),
            // Dropping one beat is harmless; the next is 10s away and the server
            // only evicts after 30s.
            to: ChatMQTTTopics.In.callHeartbeat,
            qos: .fireAndForget,
            priority: .low
        )
    }

    func sendPing(roomId: String, callId: String?) async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallPingDTO(sessionId: session, peerId: peer, roomId: roomId, callId: callId),
            to: ChatMQTTTopics.In.callPing,
            qos: .fireAndForget,
            priority: .low
        )
    }

    /// Signing out. Publishes best-effort — the session is about to be gone, so
    /// a failure here is not worth surfacing anywhere.
    func sendUserDisconnect() async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallUserDisconnectDTO(sessionId: session, userId: peer),
            to: ChatMQTTTopics.In.callUserDisconnect,
            qos: .atLeastOnce,
            priority: .high
        )
    }

    func sendReconnect(roomId: String, tryCount: Int) async throws {
        let (session, peer) = try credentials()
        try await realtime.publish(
            CallReconnectDTO(sessionId: session, peerId: peer, roomId: roomId, tryCount: tryCount),
            to: ChatMQTTTopics.In.callReconnect,
            qos: .atLeastOnce,
            priority: .high
        )
    }

    // MARK: - SFU media

    func sendIce(roomId: String, transportId: String, dtlsParameters: String) async throws {
        let (session, peer) = try credentials()
        guard let dtls = RawJSONPayload(jsonString: dtlsParameters) else {
            throw CallSignalingError.malformedParameters("dtlsParameters")
        }

        let payload = CallIceDTO(
            sessionId: session,
            roomId: roomId,
            peerId: peer,
            transportId: transportId,
            dtlsParameters: dtls
        )

        // `CALL_ICE_ANSWER` carries only `{ status }` in the documented contract,
        // so it is matched on the event type and, when the server does echo one,
        // on the transport id.
        _ = try await publishAndAwait(
            payload,
            to: ChatMQTTTopics.In.callIce,
            describing: "the transport connection",
            matching: { event in
                event.eventType == ChatMqttEvents.Call.iceAnswer
                    && (event.transportId == nil || event.transportId == transportId)
            }
        )
    }

    func sendProduce(
        roomId: String,
        transportId: String,
        kind: CallMediaKind,
        mediaType: CallMediaType,
        rtpParameters: String
    ) async throws -> String {
        let (session, peer) = try credentials()
        guard let parameters = RawJSONPayload(jsonString: rtpParameters) else {
            throw CallSignalingError.malformedParameters("rtpParameters")
        }

        let payload = CallProduceDTO(
            sessionId: session,
            roomId: roomId,
            peerId: peer,
            transportId: transportId,
            kind: kind.rawValue,
            rtpParameters: parameters,
            mediaType: mediaType.rawValue
        )

        // `call-produce` has no acknowledgement.
        //
        // The published catalogue (CALL-INTEGRATION.md §9) lists everything
        // realtime emits, and nothing answers a produce: `CALL_NEW_PRODUCER`
        // goes to the *other* peers. Yet the SFU client blocks until this
        // returns an id, so waiting for one that never comes means no media at
        // all.
        //
        // A local id is safe here because nothing is keyed by it. Every command
        // the client sends addresses a producer by peer and kind — `call-mute`
        // is `{roomId, peerId, isMuted}`, `CALL_PRODUCER_STATE` is
        // `{roomId, peerId, kind, isPaused}` — never by producer id. The server
        // already created the real producer when this payload was published.
        //
        // The short wait still catches an echo if the server ever starts
        // sending one, which the log below makes visible.
        do {
            let ack = try await publishAndAwait(
                payload,
                to: ChatMQTTTopics.In.callProduce,
                describing: "the producer",
                timeout: Self.produceEchoTimeout,
                matching: { event in
                    // Our own producer echoed back is the only plausible ack.
                    event.eventType == ChatMqttEvents.Call.newProducer
                        && event.peerId == peer
                        && event.producerId != nil
                }
            )
            if let producerId = ack.producerId {
                #if DEBUG
                print("Call produce: server acknowledged \(kind.rawValue) as \(producerId)")
                #endif
                return producerId
            }
        } catch {
            // Expected against the current contract — fall through.
        }

        let localId = Self.localProducerId(for: mediaType)
        #if DEBUG
        print("Call produce: no server ack for \(mediaType.rawValue), using \(localId)")
        #endif
        return localId
    }

    /// Camera and screen are both `kind: .video`, so the fallback id is named
    /// after the mediaType — otherwise two live producers log identically.
    static func localProducerId(for mediaType: CallMediaType) -> String {
        "local-\(mediaType.rawValue)-\(UUID().lowercasedString)"
    }

    func sendConsume(
        roomId: String,
        transportId: String,
        producerId: String,
        rtpCapabilities: String
    ) async throws -> CallConsumerParameters {
        let (session, peer) = try credentials()
        guard let capabilities = RawJSONPayload(jsonString: rtpCapabilities) else {
            throw CallSignalingError.malformedParameters("rtpCapabilities")
        }

        let payload = CallConsumeDTO(
            sessionId: session,
            roomId: roomId,
            peerId: peer,
            transportId: transportId,
            producerId: producerId,
            rtpCapabilities: capabilities
        )

        let ack = try await publishAndAwait(
            payload,
            to: ChatMQTTTopics.In.callConsume,
            describing: "the consumer",
            matching: { event in
                event.eventType == ChatMqttEvents.Call.consumerCreated
                    && event.producerId == producerId
            }
        )

        guard let parameters = CallMediaMapper.consumerParameters(from: ack) else {
            throw CallSignalingError.malformedParameters("consumer parameters")
        }
        return parameters
    }

    // MARK: - Inbound

    /// - Returns: nil when there is no session to listen for, mirroring
    ///   `ChatSyncDelegate.realtimeSubscription`. The caller retries; handing
    ///   back a stream that can never yield would strand it in `for await`.
    func observeCallEvents() async throws -> AsyncStream<InboundCallEventDTO>? {
        guard try await startInboundPumpIfNeeded() else { return nil }

        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeListener(id) }
            }
            Task { await self.addListener(id, continuation) }
        }
    }

    // MARK: - Inbound fan-out
    //
    // One subscription to the user inbox feeds both the call state machine and
    // the request/response waiters below. Subscribing twice would double the
    // traffic and let the two views of a call drift apart.

    private var listeners: [UUID: AsyncStream<InboundCallEventDTO>.Continuation] = [:]
    private var waiters: [UUID: Waiter] = [:]
    private var inboundTask: Task<Void, Never>?
    /// Which user the running pump is subscribed for. A mismatch means the
    /// subscription is stale and has to be rebuilt.
    private var pumpUserId: String?

    private struct Waiter {
        let matches: @Sendable (InboundCallEventDTO) -> Bool
        let continuation: CheckedContinuation<InboundCallEventDTO, Error>
    }

    private func addListener(
        _ id: UUID,
        _ continuation: AsyncStream<InboundCallEventDTO>.Continuation
    ) {
        listeners[id] = continuation
    }

    private func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }

    /// Subscribes the call inbox, or re-subscribes it if the user changed.
    ///
    /// The inbox topic embeds the user id, so a pump started before login sits
    /// on `waangu-chat/` forever and no call event ever arrives — the call
    /// screen then hangs on "Calling…" until the ring timeout. Remembering which
    /// user the current pump belongs to is what makes that recoverable.
    /// - Returns: whether the pump is running. `false` means there is no session
    ///   yet — an ordinary state on a signed-out app, not a failure, which is
    ///   why it is reported rather than thrown. `ChatSyncDelegate` says the same
    ///   thing by returning `nil`.
    @discardableResult
    private func startInboundPumpIfNeeded() async throws -> Bool {
        let userId = currentUserId()

        // Nothing to listen to yet. Deliberately not recorded as started, so the
        // next attempt tries again once there is a session.
        guard !userId.isEmpty else { return false }

        if inboundTask != nil {
            guard userId != pumpUserId else { return true }
            // A different user signed in on this install.
            await teardownInboundPump()
        }

        let (stream, token) = try await realtime.subscribe(
            to: ChatMQTTTopics.userInbox(userId: userId),
            as: ChatMqttJSONBox.self,
            // Every call event matters, same as chat messages. `.activityIndicator`
            // is `.debounce(1s)`: it collapses a burst — CALL_INITIATED then
            // CALL_OFFER_MEDIA then the producers — down to whichever arrived
            // last, and delays a lone event by a full second.
            buffering: .unbounded,
            qos: .atLeastOnce
        )
        // Held by the repository rather than tied to a stream's `onTermination`
        // as `ChatSyncDelegate` does. The difference is deliberate: chat has one
        // consumer per subscription, whereas this one feeds both the call state
        // machine and the request/response waiters. Cancelling it when any single
        // consumer goes away would cut off the others.
        subscriptions.add(token)
        pumpUserId = userId

        inboundTask = Task { [weak self] in
            for await box in stream {
                guard let event = CallMqttEventParser.parse(data: box.data) else { continue }
                await self?.dispatch(event)
            }
            // The transport dropped the stream. Listeners are finished so their
            // consumers fall out of `for await` and can re-attach — leaving them
            // open would strand the call manager on a stream that never yields
            // again.
            await self?.markPumpStopped()
        }

        return true
    }

    /// Drops the current subscription so the next call rebuilds it.
    ///
    /// Listeners are left in place: the call manager subscribed once at start-up
    /// and must keep receiving across reconnects and account switches.
    func detachInboundPump() async {
        await teardownInboundPump()
    }

    private func teardownInboundPump() async {
        inboundTask?.cancel()
        inboundTask = nil
        pumpUserId = nil
        await subscriptions.cancelAll()
    }

    private func markPumpStopped() {
        inboundTask = nil
        pumpUserId = nil
        finishListeners()
    }

    /// Rebuilds the subscription if it is not running. Safe to call repeatedly.
    func ensureInboundPump() async {
        try? await startInboundPumpIfNeeded()
    }

    private func dispatch(_ event: InboundCallEventDTO) {
        for (id, waiter) in waiters where waiter.matches(event) {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume(returning: event)
        }
        for listener in listeners.values {
            listener.yield(event)
        }
    }

    private func finishListeners() {
        listeners.values.forEach { $0.finish() }
        listeners.removeAll()
        for waiter in waiters.values {
            waiter.continuation.resume(throwing: CallSignalingError.notConnected)
        }
        waiters.removeAll()
    }

    // MARK: - Request / response

    private static let ackTimeout: Duration = .seconds(10)

    /// Short on purpose: the contract documents no answer to `call-produce`, so
    /// this is only a window for an echo that probably will not come, and every
    /// millisecond of it delays the call connecting.
    private static let produceEchoTimeout: Duration = .milliseconds(1500)

    /// Registers the waiter *before* publishing: an acknowledgement can arrive
    /// before `publish` has even returned.
    private func publishAndAwait<T: Encodable & Sendable>(
        _ payload: T,
        to topic: RealtimeTopic,
        describing what: String,
        timeout ackTimeout: Duration = CallSignalingRepository.ackTimeout,
        matching predicate: @escaping @Sendable (InboundCallEventDTO) -> Bool
    ) async throws -> InboundCallEventDTO {
        try await startInboundPumpIfNeeded()

        let id = UUID()
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: ackTimeout)
            guard !Task.isCancelled else { return }
            await self?.failWaiter(id, with: CallSignalingError.timedOut(what))
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            waiters[id] = Waiter(matches: predicate, continuation: continuation)
            Task {
                do {
                    try await realtime.publish(
                        payload,
                        to: topic,
                        qos: .atLeastOnce,
                        priority: .high
                    )
                } catch {
                    await self.failWaiter(id, with: error)
                }
            }
        }
    }

    /// No-op when the acknowledgement already arrived — removal is what makes
    /// the race with `dispatch` safe.
    private func failWaiter(_ id: UUID, with error: Error) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: error)
    }
}
