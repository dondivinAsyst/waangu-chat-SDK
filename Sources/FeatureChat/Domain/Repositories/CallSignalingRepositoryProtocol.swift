//
//  CallSignalingRepositoryProtocol.swift
//  FeatureChat
//
//  Outbound call signaling. Each method maps to one `waangu-chat/call-*` topic.
//  Throwing is deliberate: the UI must not claim a call is ringing when the
//  offer never left the device.
//

import Foundation
import WaanguCoreKit

protocol CallSignalingRepositoryProtocol: Sendable {

    // Setup
    func sendOffer(
        roomId: String,
        conversationId: String?,
        isVideo: Bool,
        participants: [CallParticipantDTO]
    ) async throws

    func sendJoin(roomId: String) async throws
    func sendReject(roomId: String, reason: String) async throws
    func sendDisconnect(roomId: String) async throws

    // In-call state
    func sendMute(roomId: String, isMuted: Bool) async throws
    func sendVideo(roomId: String, isVideoOff: Bool) async throws
    func sendInvitePeers(roomId: String, isVideo: Bool, participants: [CallParticipantDTO]) async throws

    // Conference features (§16). Additive: each acts inside a call that already
    // exists and never starts one.
    func sendHandRaise(roomId: String, callId: String?) async throws
    func sendHandLower(roomId: String, callId: String?) async throws
    func sendHandAck(roomId: String, callId: String?, targetUserId: String) async throws
    func sendReaction(roomId: String, reaction: String) async throws

    // SFU media
    //
    // These three are request/response rather than fire-and-forget: the media
    // engine cannot proceed without what the server sends back.

    /// Connects a transport's DTLS and waits for `CALL_ICE_ANSWER`.
    func sendIce(roomId: String, transportId: String, dtlsParameters: String) async throws

    /// Announces a local track. Returns the server-assigned producer id.
    ///
    /// `mediaType` distinguishes a camera from a screen share; both are
    /// `kind: .video`.
    func sendProduce(
        roomId: String,
        transportId: String,
        kind: CallMediaKind,
        mediaType: CallMediaType,
        rtpParameters: String
    ) async throws -> String

    /// Asks for a remote producer. Returns the consumer the server created.
    func sendConsume(
        roomId: String,
        transportId: String,
        producerId: String,
        rtpCapabilities: String
    ) async throws -> CallConsumerParameters

    /// `call-screen-share-start` — announced *after* the screen producer exists.
    /// See `CallScreenShareDTO` for why this is a second message, not the produce.
    func sendScreenShareStart(roomId: String) async throws

    /// `call-screen-share-stop`.
    func sendScreenShareStop(roomId: String) async throws

    // Keep-alive and recovery
    func sendHeartbeat(roomId: String) async throws
    func sendPing(roomId: String, callId: String?) async throws
    func sendReconnect(roomId: String, tryCount: Int) async throws

    /// Leaves every room on sign-out, so the server does not keep this user
    /// listed in a call they can no longer be reached on.
    func sendUserDisconnect() async throws

    /// Inbound call events from the user inbox, already filtered to `category == "call"`.
    ///
    /// Returns nil while there is no session to listen for — the same way
    /// `ChatSyncDelegate.realtimeSubscription` reports it. Not signed in yet is
    /// an ordinary state, so the caller should retry rather than treat it as a
    /// failure.
    func observeCallEvents() async throws -> AsyncStream<InboundCallEventDTO>?

    /// Rebuilds the inbox subscription if it is missing or stale.
    ///
    /// The inbox topic contains the user id, so a subscription made before login
    /// listens to the wrong topic and no call event ever arrives. Call this
    /// whenever the session may have changed — sign-in, sign-out, returning to
    /// the foreground.
    func ensureInboundPump() async

    /// Drops the subscription so the next `ensureInboundPump` recreates it.
    func detachInboundPump() async

    /// Brings MQTT up and attaches the call inbox before publishing.
    ///
    /// CallKit can answer while the app is still backgrounded and realtime was
    /// dropped on suspend — without this, `call-join` never leaves the device.
    func prepareForOutboundSignaling() async throws
}
